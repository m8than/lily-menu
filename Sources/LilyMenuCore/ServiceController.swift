import Darwin
import Foundation

public struct LaunchctlError: LocalizedError, Sendable {
    public var arguments: [String]
    public var status: Int32
    public var output: String

    public var errorDescription: String? {
        let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return "launchctl \(arguments.joined(separator: " ")) failed (\(status))" + (detail.isEmpty ? "" : ": \(detail)")
    }
}

public struct ServiceNotInstalledError: LocalizedError, Sendable {
    public var plistPath: String
    public var errorDescription: String? { "No launchd agent at \(plistPath). Install lily's service first." }
}

/// Everything one poll learns.
public struct Snapshot: Sendable {
    public var status: ServerStatus
    public var config: ServiceConfig?
    public var health: Health?
    /// Physical footprint of the server process (what Activity Monitor calls Memory).
    public var memoryBytes: UInt64?
    public var lastRequest: TimingsEntry?
}

/// Drives the lily launchd agent.
///
/// On means enabled and bootstrapped: launchd runs it now and again at login.
/// Off means booted out and disabled, so neither KeepAlive nor the next login
/// brings it back.
public struct ServiceController: Sendable {
    public let label: String
    public let plistURL: URL
    public let uid: uid_t

    public init(label: String, launchAgentsDirectory: URL? = nil, uid: uid_t = getuid()) {
        let dir = launchAgentsDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        self.label = label
        self.plistURL = dir.appendingPathComponent("\(label).plist")
        self.uid = uid
    }

    public var domain: String { "gui/\(uid)" }
    public var target: String { "\(domain)/\(label)" }

    /// launchd's view of the job, nil when it is not loaded.
    public func job() -> LaunchdJob? {
        let result = Shell.run("/bin/launchctl", ["print", target])
        return result.status == 0 ? LaunchdJob(launchctlPrint: result.output) : nil
    }

    public func config() -> ServiceConfig? {
        (try? ServiceConfig.load(from: plistURL)) ?? nil
    }

    public func snapshot() async -> Snapshot {
        let config = config()
        let job = job()
        var health: Health?
        var memory: UInt64?
        var last: TimingsEntry?
        if let pid = job?.pid {
            memory = Self.physicalFootprint(pid: pid)
            let base = (config ?? ServiceConfig()).baseURL
            health = await ServerAPI.get(Health.self, "health", from: base)
            if health != nil {
                last = await ServerAPI.get(TimingsList.self, "v1/timings", from: base)?.latest
            }
        }
        return Snapshot(
            status: .derive(installed: config != nil, job: job, health: health),
            config: config, health: health, memoryBytes: memory, lastRequest: last
        )
    }

    public func start() throws {
        try launchctl("enable", target)
        if job() != nil {
            try launchctl("kickstart", target)
        } else {
            guard FileManager.default.fileExists(atPath: plistURL.path) else {
                throw ServiceNotInstalledError(plistPath: plistURL.path)
            }
            // The plist's RunAtLoad starts it.
            try launchctl("bootstrap", domain, plistURL.path)
        }
    }

    public func stop() throws {
        try launchctl("disable", target)
        if job() != nil {
            try launchctl("bootout", target)
        }
    }

    /// SIGTERM, wait for the process to exit, start again. The old process
    /// holds the model's memory and lily's instance lock until it has spilled
    /// its sessions and exited; a new one started earlier would ask for two
    /// models' worth of memory or be refused by the lock.
    public func restart(timeout: Duration = .seconds(120)) async throws {
        guard let pid = job()?.pid else { return try start() }
        // lily exits 0 on SIGTERM, which KeepAlive {SuccessfulExit: false} leaves down.
        try launchctl("kill", "SIGTERM", target)
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while kill(pid, 0) == 0, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(500))
        }
        try launchctl("kickstart", target)
    }

    @discardableResult
    func launchctl(_ arguments: String...) throws -> String {
        let result = Shell.run("/bin/launchctl", arguments)
        guard result.status == 0 else {
            throw LaunchctlError(arguments: arguments, status: result.status, output: result.output)
        }
        return result.output
    }

    static func physicalFootprint(pid: Int32) -> UInt64? {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return status == 0 ? info.ri_phys_footprint : nil
    }
}

enum Shell {
    static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, "\(error)") }
        // Read before waiting: a full pipe would block the child forever.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
