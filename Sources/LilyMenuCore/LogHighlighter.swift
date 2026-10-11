import Foundation

/// What a whole log line is about.
public enum LogTone: Sendable, Equatable {
    /// Something failed.
    case error
    case warning
    /// The model is up: `ready:`, `loaded …`, `listening on …`.
    case success
    /// Shutting down, unloading, signals.
    case lifecycle
    /// One completed request (`chatcmpl-…: …`).
    case request
}

/// A highlighted part of a line.
public enum LogToken: Sendable, Equatable {
    /// `session cache:` at the start of a line.
    case prefix
    /// A number, with its unit if it has one.
    case number
    /// A throughput such as `112.1 tok/s`.
    case rate
    case requestID
    case url
    case path
    /// The `finish=` of `finish=stop`.
    case key
}

public enum LogStyle: Sendable, Equatable {
    case line(LogTone)
    case token(LogToken)
}

/// A styled range, in UTF-16 units of the highlighted text.
public struct LogSpan: Sendable, Equatable {
    public var range: NSRange
    public var style: LogStyle

    public init(_ range: NSRange, _ style: LogStyle) {
        self.range = range
        self.style = style
    }
}

private func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
    try! NSRegularExpression(pattern: pattern, options: options)
}

/// The compiled patterns. NSRegularExpression is immutable and safe to share
/// across threads; older SDKs just do not mark it Sendable.
private final class Patterns: @unchecked Sendable {
    // Line tones, checked in this order.
    let errorLine = regex(
        #"^Error\b|\b(error|failed|failure|panic(ked)?|fault|cannot|could not|refused [1-9])"#, .caseInsensitive)
    let warningLine = regex(
        #"\b(warn(ing)?|retry(ing)?|dropping|timed out|timeout)\b|^--- log was"#, .caseInsensitive)
    let requestLine = regex(#"^(chat)?cmpl-\S+:"#)
    let successLine = regex(#"^(ready:|loaded |listening on )"#)
    let lifecycleLine = regex(
        #"^(SIGTERM|SIGINT|stopping|exiting|unloading|unloaded|reloading|idle|released pin)\b|^stopped$"#)

    // Tokens, in application order: later ones win where they overlap.
    let prefix = regex(#"^[A-Za-z][A-Za-z0-9 /_-]{0,40}?:(?=\s)"#)
    let number = regex(#"(?<![\w.])\d+(?:\.\d+)?(?:\s?(?:GB|MB|KB|B|ms|s|m|h|%)(?![\w/]))?(?![\w.])"#)
    let key = regex(#"\b[a-z_]+="#)
    let path = regex(#"(?<![\w:/.])/(?:[\w.@-]+/)+[\w.@-]*"#)
    let url = regex(#"https?://[^\s)]+"#)
    let rate = regex(#"\d+(?:\.\d+)?\s?tok/s"#)
    let requestID = regex(#"^(chat)?cmpl-[\w-]+"#)
}

/// Highlighting rules for lily's log. Later spans are meant to be applied over earlier ones.
public enum LogHighlighter {
    private static let patterns = Patterns()

    /// Spans for every line of `text`, with ranges relative to `text`.
    public static func highlight(_ text: String) -> [LogSpan] {
        let string = text as NSString
        var spans: [LogSpan] = []
        var location = 0
        while location < string.length {
            var end = 0
            var contentsEnd = 0
            string.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let line = NSRange(location: location, length: contentsEnd - location)
            spans += highlightLine(string, line)
            location = end
        }
        return spans
    }

    static func highlightLine(_ string: NSString, _ line: NSRange) -> [LogSpan] {
        guard line.length > 0 else { return [] }
        func matches(_ regex: NSRegularExpression) -> [NSRange] {
            regex.matches(in: string as String, range: line).map(\.range)
        }
        func first(_ regex: NSRegularExpression) -> Bool {
            regex.firstMatch(in: string as String, range: line) != nil
        }
        let p = patterns
        var spans: [LogSpan] = []
        let tone: LogTone? =
            first(p.errorLine) ? .error
            : first(p.warningLine) ? .warning
            : first(p.requestLine) ? .request
            : first(p.successLine) ? .success
            : first(p.lifecycleLine) ? .lifecycle
            : nil
        if let tone { spans.append(LogSpan(line, .line(tone))) }

        if tone != .request {
            spans += matches(p.prefix).map { LogSpan($0, .token(.prefix)) }
        }
        spans += matches(p.number).map { LogSpan($0, .token(.number)) }
        spans += matches(p.key).map { LogSpan($0, .token(.key)) }
        spans += matches(p.path).map { LogSpan($0, .token(.path)) }
        spans += matches(p.url).map { LogSpan($0, .token(.url)) }
        spans += matches(p.rate).map { LogSpan($0, .token(.rate)) }
        spans += matches(p.requestID).map { LogSpan($0, .token(.requestID)) }
        return spans
    }
}
