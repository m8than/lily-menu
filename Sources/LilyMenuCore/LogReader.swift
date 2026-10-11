import Foundation

/// What a poll of the log found.
public enum LogUpdate: Equatable, Sendable {
    /// Complete new lines.
    case append(String)
    /// The file was truncated or replaced; this is its content from the start.
    case restart(String)
}

/// Follows a growing log file, like `tail -F`: the last part of the file
/// first, then whole lines as they are appended. Survives the file being
/// missing, truncated or replaced.
public struct LogReader: Sendable {
    public let path: String
    /// How much of an existing file the first poll returns.
    public let initialBytes: UInt64

    private var file: (device: dev_t, inode: ino_t)?
    private var offset: UInt64 = 0
    /// Bytes after the last newline: a line still being written.
    private var partial = Data()
    /// The first poll started mid-file: drop bytes through the next newline.
    private var skipToLineStart = false

    public init(path: String, initialBytes: UInt64 = 512 * 1024) {
        self.path = path
        self.initialBytes = initialBytes
    }

    /// Reads whatever was appended since the last poll; nil when nothing new.
    public mutating func poll() -> LogUpdate? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        let identity = (device: info.st_dev, inode: info.st_ino)
        let size = UInt64(info.st_size)

        var restarted = false
        if let file, file.device == identity.device, file.inode == identity.inode, size >= offset {
            // The same file, grown or unchanged.
        } else if file == nil {
            // First look: the last initialBytes, from the first line that starts
            // inside them. Reading from one byte earlier keeps a line that
            // starts exactly at the window's edge.
            if size > initialBytes {
                offset = size - initialBytes - 1
                skipToLineStart = true
            }
        } else {
            // Truncated or replaced: read the new content from the start.
            offset = 0
            restarted = true
            skipToLineStart = false
            partial.removeAll()
        }
        file = identity
        guard size > offset else { return restarted ? .restart("") : nil }

        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        let chunk = (try? handle.read(upToCount: Int(size - offset))) ?? Data()
        offset += UInt64(chunk.count)

        var bytes = partial + chunk
        if skipToLineStart {
            guard let newline = bytes.firstIndex(of: UInt8(ascii: "\n")) else { return nil }
            skipToLineStart = false
            bytes = bytes[(newline + 1)...]
        }
        guard let lastNewline = bytes.lastIndex(of: UInt8(ascii: "\n")) else {
            partial = Data(bytes)
            return restarted ? .restart("") : nil
        }
        partial = Data(bytes[(lastNewline + 1)...])
        let text = String(decoding: bytes[...lastNewline], as: UTF8.self)
        return restarted ? .restart(text) : .append(text)
    }
}
