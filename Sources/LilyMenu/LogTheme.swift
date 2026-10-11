import AppKit
import LilyMenuCore

extension NSAttributedString.Key {
    /// Full-width tint behind a line (NSColor, already translucent).
    static let lilyLineBand = NSAttributedString.Key("lilyLineBand")
    /// The stripe at the left edge of a line (NSColor).
    static let lilyLineStripe = NSAttributedString.Key("lilyLineStripe")
}

/// How each `LogStyle` looks. System colors follow light and dark mode.
@MainActor
enum LogTheme {
    static let fontSize: CGFloat = 12
    static let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    static let boldFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)

    static let base: [NSAttributedString.Key: Any] = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = LogTheme.lineGap
        // Wrapped continuation lines are indented so each log line stands apart.
        let indent = ("  " as NSString).size(withAttributes: [.font: font]).width
        paragraph.headIndent = indent
        return [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]
    }()

    /// Space after each log line, left unpainted so adjacent bands stay apart.
    nonisolated static let lineGap: CGFloat = 2

    /// Xcode's colors for number literals.
    private static let numberColor = dynamic(
        light: NSColor(srgbRed: 0.11, green: 0.0, blue: 0.81, alpha: 1),
        dark: NSColor(srgbRed: 0.85, green: 0.79, blue: 0.49, alpha: 1))

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }

    private static func line(_ color: NSColor, band: CGFloat, text: NSColor? = nil) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .lilyLineBand: color.withAlphaComponent(band),
            .lilyLineStripe: color,
        ]
        if let text { attributes[.foregroundColor] = text }
        return attributes
    }

    static func attributes(for style: LogStyle) -> [NSAttributedString.Key: Any] {
        switch style {
        case .line(.error): return line(.systemRed, band: 0.16, text: .systemRed)
        case .line(.warning): return line(.systemOrange, band: 0.14)
        case .line(.success): return line(.systemGreen, band: 0.14)
        case .line(.lifecycle): return line(.systemPurple, band: 0.11)
        case .line(.request): return line(.systemBlue, band: 0.06)
        case .token(.prefix): return [.font: boldFont, .foregroundColor: NSColor.systemIndigo]
        case .token(.number): return [.foregroundColor: numberColor]
        case .token(.rate): return [.font: boldFont, .foregroundColor: NSColor.systemGreen]
        case .token(.requestID): return [.font: boldFont, .foregroundColor: NSColor.systemBlue]
        case .token(.path): return [.foregroundColor: NSColor.systemTeal]
        case .token(.key): return [.foregroundColor: NSColor.secondaryLabelColor]
        case .token(.url): return [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        }
    }

    static func attributedString(_ text: String, spans: [LogSpan]) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: base)
        for span in spans {
            result.addAttributes(attributes(for: span.style), range: span.range)
            if span.style == .token(.url), let url = URL(string: (text as NSString).substring(with: span.range)) {
                result.addAttribute(.link, value: url, range: span.range)
            }
        }
        return result
    }
}

/// Draws each line's band and stripe across the full width of the view, and
/// marks the line the reader clicked.
final class LogLayoutManager: NSLayoutManager {
    /// Character range of the highlighted line.
    var currentLine: NSRange?

    /// NSTextView clips background drawing to the text container, so the stripe
    /// sits at the container's left edge, inside its line fragment padding.
    private func stripe(_ row: NSRect) -> NSRect {
        NSRect(x: row.minX, y: row.minY, width: 3, height: row.height)
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if let storage = textStorage, let textView = firstTextView {
            // AppKit draws on the main thread.
            let width = MainActor.assumeIsolated {
                max(textView.bounds.width, textView.enclosingScrollView?.contentSize.width ?? 0)
            }
            let current = currentLine
            enumerateLineFragments(forGlyphRange: glyphsToShow) { rect, _, _, glyphRange, _ in
                let index = self.characterIndexForGlyph(at: glyphRange.location)
                guard index < storage.length else { return }
                // The last fragment of a log line carries its paragraph spacing; leave that unpainted.
                let end = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
                let endsLine = NSMaxRange(end) >= storage.length
                    || (storage.string as NSString).character(at: NSMaxRange(end) - 1) == 0x0A
                let height = rect.height - (endsLine ? LogTheme.lineGap : 0)
                let row = NSRect(x: origin.x, y: rect.minY + origin.y, width: width, height: height)
                if let band = storage.attribute(.lilyLineBand, at: index, effectiveRange: nil) as? NSColor {
                    band.setFill()
                    row.fill(using: .sourceOver)
                }
                if let current, NSLocationInRange(index, current) {
                    NSColor.selectedContentBackgroundColor.withAlphaComponent(0.18).setFill()
                    row.fill(using: .sourceOver)
                    NSColor.selectedContentBackgroundColor.setFill()
                    self.stripe(row).fill(using: .sourceOver)
                } else if let stripe = storage.attribute(.lilyLineStripe, at: index, effectiveRange: nil) as? NSColor {
                    stripe.setFill()
                    self.stripe(row).fill(using: .sourceOver)
                }
            }
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }
}
