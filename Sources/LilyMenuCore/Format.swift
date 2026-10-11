import Foundation

public enum Format {
    /// Binary gigabytes, as Activity Monitor shows memory.
    public static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }

    /// "31 tokens at 107.5 tok/s, prompt 43 (0 cached) at 233.5 tok/s, 2 min ago"
    public static func request(_ entry: TimingsEntry, now: Date = Date()) -> String {
        let t = entry.timings
        let age = RelativeDateTimeFormatter()
        age.unitsStyle = .abbreviated
        return String(
            format: "%d tokens at %.1f tok/s, prompt %d (%d cached) at %.1f tok/s, %@",
            t.generatedTokens, t.decodePerSecond, t.promptTokens, t.cachedTokens, t.prefillPerSecond,
            age.localizedString(for: entry.createdDate, relativeTo: now)
        )
    }
}
