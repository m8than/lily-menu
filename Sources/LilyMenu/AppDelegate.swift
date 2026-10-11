import AppKit
import ServiceManagement

/// User defaults the app reads (`defaults write com.lily.menu <key> <value>`).
enum Preference {
    /// launchd label of the lily agent.
    static let serviceLabel = "ServiceLabel"
    /// Seconds between polls.
    static let pollInterval = "PollInterval"
    /// Set once the app has registered itself to open at login on first launch.
    static let loginItemConfigured = "LoginItemConfigured"
    /// Whether the log window wraps long lines.
    static let wrapLogLines = "WrapLogLines"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menu: StatusMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Preference.serviceLabel: "com.lily.server",
            Preference.pollInterval: 3.0,
            Preference.wrapLogLines: true,
        ])
        // Open at login by default, once; the menu's checkbox turns it off for good.
        if !defaults.bool(forKey: Preference.loginItemConfigured) {
            try? SMAppService.mainApp.register()
            defaults.set(true, forKey: Preference.loginItemConfigured)
        }
        menu = StatusMenu(
            label: defaults.string(forKey: Preference.serviceLabel) ?? "com.lily.server",
            pollInterval: max(1, defaults.double(forKey: Preference.pollInterval))
        )
    }
}
