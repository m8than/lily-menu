import AppKit
import LilyMenuCore
import ServiceManagement

private let serviceSetupURL = URL(string: "https://github.com/fabiogreter/lily-qwen3.8-flash-next/blob/main/tools/service/README.md")!

/// The status item and its menu.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let controller: ServiceController
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let statusLine = NSMenuItem()
    private let modelLine = NSMenuItem()
    private let memoryLine = NSMenuItem()
    private let requestLine = NSMenuItem()
    private lazy var toggleItem = action("Start Server", #selector(toggle), "s")
    private lazy var restartItem = action("Restart Server", #selector(restart), "r")
    private lazy var copyItem = action("Copy API URL", #selector(copyAPIURL), "c")
    private lazy var logItem = action("Show Server Log", #selector(openLog), "l")
    private lazy var setupItem = action("How to Install the Service…", #selector(openSetupGuide), "")
    private lazy var loginItem = action("Open at Login", #selector(toggleLoginItem), "")

    private var snapshot: Snapshot?
    /// Set while a start, stop or restart runs; shown instead of the polled state.
    private var pending: ServerStatus?
    private var polling = false
    private var logWindow: LogWindow?

    init(label: String, pollInterval: TimeInterval) {
        controller = ServiceController(label: label)
        super.init()
        for line in [statusLine, modelLine, memoryLine, requestLine] { line.isEnabled = false }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let versionLine = NSMenuItem(title: "LilyMenu \(version)", action: nil, keyEquivalent: "")
        versionLine.isEnabled = false
        let quit = NSMenuItem(title: "Quit LilyMenu", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.toolTip = "The server keeps running or stays off; quitting only removes the menu."
        [statusLine, modelLine, memoryLine, requestLine, .separator(),
         toggleItem, restartItem, .separator(),
         copyItem, logItem, setupItem, .separator(),
         loginItem, versionLine, quit].forEach(menu.addItem)
        menu.delegate = self
        item.menu = menu
        render()
        refresh()
        Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func action(_ title: String, _ selector: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: Polling

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    private func refresh() {
        guard !polling else { return }
        polling = true
        let controller = controller
        Task {
            let snapshot = await Task.detached { await controller.snapshot() }.value
            self.snapshot = snapshot
            self.polling = false
            self.render()
        }
    }

    private func render() {
        let status = pending ?? snapshot?.status ?? .starting
        let health = snapshot?.health
        statusLine.title = "lily: \(status.title)"

        modelLine.title = health?.model.map { "Model: \($0)" } ?? ""
        modelLine.isHidden = health?.model == nil

        memoryLine.title = snapshot?.memoryBytes.map { "Memory: \(Format.gigabytes($0))" } ?? ""
        memoryLine.isHidden = snapshot?.memoryBytes == nil

        if let last = snapshot?.lastRequest {
            requestLine.title = "Last request: \(Format.request(last))"
            requestLine.isHidden = false
        } else {
            requestLine.isHidden = true
        }

        let busy = pending != nil
        toggleItem.title = status.isUp ? "Stop Server" : "Start Server"
        toggleItem.isEnabled = !busy && status != .stopping && status != .notInstalled
        restartItem.isEnabled = !busy && status.isUp
        copyItem.title = "Copy API URL (\((snapshot?.config ?? ServiceConfig()).apiBaseURL))"
        logItem.isEnabled = snapshot?.config?.logPath != nil
        setupItem.isHidden = status != .notInstalled
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        loginItem.title = SMAppService.mainApp.status == .requiresApproval
            ? "Open at Login (approve in System Settings)" : "Open at Login"

        guard let button = item.button else { return }
        let image = NSImage(systemSymbolName: status.symbolName, accessibilityDescription: "lily: \(status.title)")
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = status.isDimmed
        button.toolTip = "lily: \(status.title)"
    }

    // MARK: Actions

    private func perform(showing status: ServerStatus, _ work: @escaping @Sendable (ServiceController) async throws -> Void) {
        pending = status
        render()
        let controller = controller
        Task {
            let error: Error? = await Task.detached {
                do { try await work(controller); return nil } catch { return error }
            }.value
            self.pending = nil
            self.refresh()
            if let error { self.alert("lily could not be controlled", error.localizedDescription) }
        }
    }

    @objc private func toggle() {
        if (snapshot?.status ?? .off).isUp {
            perform(showing: .stopping) { try $0.stop() }
        } else {
            perform(showing: .starting) { try $0.start() }
        }
    }

    @objc private func restart() {
        perform(showing: .stopping) { try await $0.restart() }
    }

    @objc private func copyAPIURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString((snapshot?.config ?? ServiceConfig()).apiBaseURL, forType: .string)
    }

    @objc private func openLog() {
        guard let path = snapshot?.config?.logPath else { return }
        if let logWindow {
            logWindow.show(path: path)
        } else {
            let window = LogWindow(path: path)
            logWindow = window
            window.show(path: path)
        }
    }

    @objc private func openSetupGuide() {
        NSWorkspace.shared.open(serviceSetupURL)
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled: try service.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default: try service.register()
            }
        } catch {
            alert("Could not change the login item", error.localizedDescription)
        }
        render()
    }

    private func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
