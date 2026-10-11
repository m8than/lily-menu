import Foundation
import Testing
@testable import LilyMenuCore

/// A log file in a fresh temporary directory.
private struct TempLog {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lilylog-\(UUID())")
    var path: String { dir.appendingPathComponent("server.log").path }

    init() { try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }

    func write(_ text: String) { try! Data(text.utf8).write(to: URL(fileURLWithPath: path)) }

    func append(_ text: String) {
        let handle = FileHandle(forWritingAtPath: path)!
        handle.seekToEndOfFile()
        handle.write(Data(text.utf8))
        try! handle.close()
    }

    func remove() { try? FileManager.default.removeItem(at: dir) }
}

@Test func followsAppendedLinesAndHoldsBackPartialOnes() {
    let log = TempLog()
    defer { log.remove() }
    log.write("one\ntwo\n")
    var reader = LogReader(path: log.path)
    #expect(reader.poll() == .append("one\ntwo\n"))
    #expect(reader.poll() == nil)

    log.append("thr")
    #expect(reader.poll() == nil)
    log.append("ee\nfour")
    #expect(reader.poll() == .append("three\n"))
    log.append("\n")
    #expect(reader.poll() == .append("four\n"))
}

@Test func multibyteCharactersSplitAcrossWritesSurvive() {
    let log = TempLog()
    defer { log.remove() }
    log.write("")
    var reader = LogReader(path: log.path)
    _ = reader.poll()
    let bytes = Array("µs ✓\n".utf8)
    let handle = FileHandle(forWritingAtPath: log.path)!
    handle.write(Data(bytes[..<1]))  // half of "µ"
    #expect(reader.poll() == nil)
    handle.write(Data(bytes[1...]))
    try! handle.close()
    #expect(reader.poll() == .append("µs ✓\n"))
}

@Test func firstPollStartsAtALineInsideTheWindow() {
    let log = TempLog()
    defer { log.remove() }
    log.write("aaaa\nbbbb\ncccc\n")  // 15 bytes, lines start at 0, 5, 10
    var midLine = LogReader(path: log.path, initialBytes: 7)  // window starts inside "bbbb"
    #expect(midLine.poll() == .append("cccc\n"))
    var atLineStart = LogReader(path: log.path, initialBytes: 10)  // window starts exactly at "bbbb"
    #expect(atLineStart.poll() == .append("bbbb\ncccc\n"))
}

@Test func truncationRestartsFromTheBeginning() {
    let log = TempLog()
    defer { log.remove() }
    log.write("old line one\nold line two\n")
    var reader = LogReader(path: log.path)
    _ = reader.poll()
    log.write("new\n")  // same file, shorter
    #expect(reader.poll() == .restart("new\n"))
    log.append("more\n")
    #expect(reader.poll() == .append("more\n"))
}

@Test func replacedFileIsReadFromTheBeginning() throws {
    let log = TempLog()
    defer { log.remove() }
    log.write("before\n")
    var reader = LogReader(path: log.path)
    _ = reader.poll()
    let replacement = log.dir.appendingPathComponent("next.log")
    try Data("after rotation, longer than before\n".utf8).write(to: replacement)
    _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: log.path), withItemAt: replacement)
    #expect(reader.poll() == .restart("after rotation, longer than before\n"))
}

@Test func waitsForAFileThatDoesNotExistYet() {
    let log = TempLog()
    defer { log.remove() }
    var reader = LogReader(path: log.path)
    #expect(reader.poll() == nil)
    log.write("ready: serving\n")
    #expect(reader.poll() == .append("ready: serving\n"))
}
