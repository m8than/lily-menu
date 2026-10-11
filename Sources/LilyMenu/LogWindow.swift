import AppKit
import LilyMenuCore

/// A window that follows lily's log as it is written, like `tail -F`, with
/// lines colored by what they report.
@MainActor
final class LogWindow: NSObject, NSWindowDelegate, NSTextViewDelegate {
    /// Characters kept in the view; older lines are dropped past this.
    private static let maxCharacters = 4_000_000
    nonisolated private static let restartMarker = "--- log was truncated or replaced ---\n"

    private let window: NSWindow
    private let textView: NSTextView
    private let layoutManager = LogLayoutManager()
    private let statusLabel = NSTextField(labelWithString: "")
    private var path: String
    private var reader: LogReader
    private var timer: Timer?
    private var reading = false

    init(path: String) {
        self.path = path
        reader = LogReader(path: path)

        // TextKit 1, so the layout manager can draw full-width line backgrounds.
        let storage = NSTextStorage()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        textView = NSTextView(frame: .zero, textContainer: container)
        textView.isEditable = false
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 4, height: 8)
        container.lineFragmentPadding = 12
        textView.typingAttributes = LogTheme.base
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder

        window = KeyCommandWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.minSize = NSSize(width: 480, height: 240)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("LilyLogWindow")
        super.init()
        window.delegate = self
        textView.delegate = self
        (window as! KeyCommandWindow).textView = textView

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let wrap = NSButton(checkboxWithTitle: "Wrap Lines", target: self, action: #selector(toggleWrap))
        wrap.state = UserDefaults.standard.bool(forKey: Preference.wrapLogLines) ? .on : .off
        let clear = NSButton(title: "Clear", target: self, action: #selector(clear))
        let reveal = NSButton(title: "Show in Finder", target: self, action: #selector(reveal))
        for button in [wrap, clear, reveal] { button.controlSize = .small }
        let bar = NSStackView(views: [statusLabel, wrap, clear, reveal])
        bar.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        bar.setHuggingPriority(.defaultHigh, for: .vertical)

        let content = NSStackView(views: [scroll, bar])
        content.orientation = .vertical
        content.spacing = 0
        window.contentView = content
        setWrapping(wrap.state == .on)
        updateTitle()
    }

    /// Shows the window and starts following `path` (which may change with the plist).
    func show(path: String) {
        if path != self.path {
            self.path = path
            reader = LogReader(path: path)
            clear()
            updateTitle()
        }
        if !window.isVisible { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        startFollowing()
    }

    private func updateTitle() {
        window.title = "lily log: \((path as NSString).lastPathComponent)"
        window.representedURL = URL(fileURLWithPath: path)
    }

    private func startFollowing() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Reading

    private struct Chunk: Sendable {
        var text: String
        var spans: [LogSpan]
        var restart: Bool
    }

    private func poll() {
        guard !reading else { return }
        reading = true
        let reader = reader
        let path = path
        Task {
            // Reading and highlighting happen off the main thread.
            let (chunk, advanced, exists) = await Task.detached {
                var reader = reader
                let chunk: Chunk? = switch reader.poll() {
                case .append(let text)?: Chunk(text: text, spans: LogHighlighter.highlight(text), restart: false)
                case .restart(let text)?:
                    Chunk(text: Self.restartMarker + text,
                          spans: LogHighlighter.highlight(Self.restartMarker + text), restart: true)
                case nil: nil
                }
                return (chunk, reader, FileManager.default.fileExists(atPath: path))
            }.value
            reading = false
            // A path change while reading started a new reader; drop this result.
            guard path == self.path else { return }
            self.reader = advanced
            if let chunk { apply(chunk) }
            statusLabel.stringValue = exists ? "Following \(path)" : "Waiting for \(path) to be created…"
        }
    }

    private func apply(_ chunk: Chunk) {
        guard let storage = textView.textStorage else { return }
        let atBottom = isScrolledToBottom
        let styled = LogTheme.attributedString(chunk.text, spans: chunk.spans)
        storage.beginEditing()
        if chunk.restart {
            storage.setAttributedString(styled)
            layoutManager.currentLine = nil
        } else {
            storage.append(styled)
        }
        if storage.length > Self.maxCharacters {
            let excess = storage.length - Self.maxCharacters
            let newline = (storage.string as NSString).range(
                of: "\n", range: NSRange(location: excess, length: storage.length - excess))
            storage.deleteCharacters(in: NSRange(
                location: 0, length: newline.location == NSNotFound ? excess : newline.location + 1))
            layoutManager.currentLine = nil
        }
        storage.endEditing()
        // Follow new lines only while the reader is at the end, so scrolling
        // up to read something is not interrupted.
        if atBottom { textView.scrollToEndOfDocument(nil) }
    }

    private var isScrolledToBottom: Bool {
        guard let clip = textView.enclosingScrollView?.contentView else { return true }
        return clip.bounds.maxY >= textView.bounds.maxY - 20
    }

    // MARK: Current line

    func textViewDidChangeSelection(_ notification: Notification) {
        let string = textView.string as NSString
        let location = textView.selectedRange().location
        let line = string.length == 0
            ? nil : string.lineRange(for: NSRange(location: min(location, string.length - 1), length: 0))
        let previous = layoutManager.currentLine
        guard line != previous else { return }
        layoutManager.currentLine = line
        for range in [previous, line].compactMap({ $0 }) where NSMaxRange(range) <= string.length {
            layoutManager.invalidateDisplay(forCharacterRange: range)
        }
    }

    // MARK: Controls

    @objc private func toggleWrap(_ sender: NSButton) {
        let wrap = sender.state == .on
        UserDefaults.standard.set(wrap, forKey: Preference.wrapLogLines)
        setWrapping(wrap)
    }

    /// Wrapped lines fit the window; unwrapped ones scroll sideways, as in a terminal.
    private func setWrapping(_ wrap: Bool) {
        guard let scroll = textView.enclosingScrollView, let container = textView.textContainer else { return }
        let unbounded = CGFloat.greatestFiniteMagnitude
        scroll.hasHorizontalScroller = !wrap
        textView.isHorizontallyResizable = !wrap
        container.widthTracksTextView = wrap
        if wrap {
            textView.setFrameSize(NSSize(width: scroll.contentSize.width, height: textView.frame.height))
            container.containerSize = NSSize(width: scroll.contentSize.width, height: unbounded)
        } else {
            container.containerSize = NSSize(width: unbounded, height: unbounded)
        }
    }

    @objc private func clear() {
        layoutManager.currentLine = nil
        textView.textStorage?.setAttributedString(NSAttributedString())
    }

    @objc private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

/// An accessory app has no visible menu bar, so the usual ⌘F, ⌘G, ⌘C, ⌘A
/// and ⌘W menu shortcuts are handled here.
private final class KeyCommandWindow: NSWindow {
    weak var textView: NSTextView?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.shift) == .command,
              let key = event.charactersIgnoringModifiers?.lowercased(), let textView
        else { return super.performKeyEquivalent(with: event) }
        let shift = event.modifierFlags.contains(.shift)
        func find(_ action: NSTextFinder.Action) {
            let sender = NSMenuItem()
            sender.tag = action.rawValue
            textView.performTextFinderAction(sender)
        }
        switch key {
        case "f": find(.showFindInterface)
        case "g": find(shift ? .previousMatch : .nextMatch)
        case "e": find(.setSearchString)
        case "c": textView.copy(nil)
        case "a": textView.selectAll(nil)
        case "w": performClose(nil)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}
