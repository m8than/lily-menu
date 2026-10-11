import Foundation

/// The fields of `launchctl print gui/<uid>/<label>` the menu needs.
public struct LaunchdJob: Equatable, Sendable {
    /// The running process, nil between runs.
    public var pid: Int32?
    /// `last exit code` verbatim: a number, or `(never exited)`.
    public var lastExitCode: String?

    public init(pid: Int32? = nil, lastExitCode: String? = nil) {
        self.pid = pid
        self.lastExitCode = lastExitCode
    }

    /// Parses `launchctl print` output. Only the job's own lines (indented
    /// one tab) count; deeper lines belong to nested dictionaries such as
    /// the environment or endpoints.
    public init(launchctlPrint text: String) {
        self.init()
        for line in text.split(separator: "\n") {
            guard line.hasPrefix("\t"), !line.hasPrefix("\t\t") else { continue }
            let body = line.dropFirst()
            guard let eq = body.range(of: " = ") else { continue }
            let value = String(body[eq.upperBound...])
            switch body[..<eq.lowerBound] {
            case "pid" where pid == nil: pid = Int32(value)
            case "last exit code" where lastExitCode == nil: lastExitCode = value
            default: break
            }
        }
    }
}
