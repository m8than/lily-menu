import Foundation
import Testing
@testable import LilyMenuCore

private func tone(_ line: String) -> LogTone? {
    for span in LogHighlighter.highlight(line) {
        if case .line(let tone) = span.style { return tone }
    }
    return nil
}

/// The texts of `line` that end up styled as `token`.
private func tokens(_ token: LogToken, in line: String) -> [String] {
    LogHighlighter.highlight(line)
        .filter { $0.style == .token(token) }
        .map { (line as NSString).substring(with: $0.range) }
}

// Lines below are lily's own output.

@Test(arguments: [
    ("ready: serving Qwen3.8-Flash-Next on http://127.0.0.1:8000 (unloading after 30m idle)", LogTone.success),
    ("loaded Qwen3.8-Flash-Next in 10.2s (74.9 GB resident, 0.90 GB of it the vision tower)", .success),
    ("SIGTERM: stopping (no new requests; a running request has 10s to finish)", .lifecycle),
    ("stopped", .lifecycle),
    ("chatcmpl-1791681135-1: 43 prompt tokens (0 cached), 22 generated, decode 0.20s (112.1 tok/s)", .request),
    ("session cache: spilling to disk failed: No space left on device", .error),
    ("request failed on a GPU fault (the engine reloads): timeout", .error),
    ("Error: model directory not found", .error),
])
func linesGetTheirTone(line: String, expected: LogTone) {
    #expect(tone(line) == expected)
}

@Test(arguments: [
    // "memory pressure" and "0 dropped" are routine, not problems.
    "weights: pinning 74.9 GB in memory from the first request on, released after 1m without a request or under memory pressure",
    "stopping: unloaded Qwen3.8-Flash-Next in 0.6s (75.3 GB was resident; 0 sessions spilled to disk, 0 dropped, in 0.5s)",
    "defaults: temperature 1 top_k 20 top_p 0.95 min_p 0 repetition_penalty 1",
    "stopping: refused 0 queued requests",
])
func routineLinesAreNotErrors(line: String) {
    #expect(tone(line) != .error)
    #expect(tone(line) != .warning)
}

@Test func requestLineHighlightsIdAndRateButNoPrefix() {
    let line = "chatcmpl-1791681184-2: 43 prompt tokens (42 cached), 22 generated, decode 0.21s (106.0 tok/s), finish=stop"
    #expect(tokens(.requestID, in: line) == ["chatcmpl-1791681184-2"])
    #expect(tokens(.rate, in: line) == ["106.0 tok/s"])
    #expect(tokens(.prefix, in: line).isEmpty)
    #expect(tokens(.key, in: line) == ["finish="])
}

@Test func numbersKeepUnitsButSkipIdentifiers() {
    let line = "session cache: disk tier at /Users/me/Library/Caches/lily/sessions/qwen4_exp_kv_2x256_q8 (0.0/107.4 GB, 18304 B/token, 5 sessions)"
    #expect(tokens(.prefix, in: line) == ["session cache:"])
    #expect(tokens(.number, in: line) == ["0.0", "107.4 GB", "18304", "5"])
    #expect(tokens(.path, in: line) == ["/Users/me/Library/Caches/lily/sessions/qwen4_exp_kv_2x256_q8"])
}

@Test func urlsAreNotPaths() {
    let line = "listening on http://127.0.0.1:8000 (loading model)"
    #expect(tokens(.url, in: line) == ["http://127.0.0.1:8000"])
    #expect(tokens(.path, in: line).isEmpty)
    #expect(tokens(.prefix, in: line).isEmpty)
}

@Test func spansAreRelativeToTheWholeText() {
    let text = "stopped\nready: serving on http://127.0.0.1:8000\n"
    let url = LogHighlighter.highlight(text).first { $0.style == .token(.url) }
    #expect(url.map { (text as NSString).substring(with: $0.range) } == "http://127.0.0.1:8000")
}
