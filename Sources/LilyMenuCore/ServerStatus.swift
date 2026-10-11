/// What the menu bar shows, derived from launchd's view of the job and lily's `/health`.
public enum ServerStatus: Equatable, Sendable {
    /// No plist in ~/Library/LaunchAgents and no loaded job.
    case notInstalled
    /// Not loaded, or loaded and stopped cleanly.
    case off
    /// The process runs but `/health` does not answer yet.
    case starting
    case loading
    case ready
    /// The model was unloaded after `--idle-unload`; the next request reloads it.
    case idle
    case reloading
    /// Requests are queued, but something went wrong; see the log.
    case recovering
    case stopping
    /// Exit 75: another lily process holds the instance lock; launchd retries every 30 s.
    case waitingForLock
    /// Exited with an error; launchd's KeepAlive restarts it.
    case crashed(exitCode: String)

    public static func derive(installed: Bool, job: LaunchdJob?, health: Health?) -> ServerStatus {
        guard let job else { return installed ? .off : .notInstalled }
        if job.pid != nil {
            switch health?.state {
            case "ready": return .ready
            case "idle": return .idle
            case "loading": return .loading
            case "reloading": return .reloading
            case "recovering": return .recovering
            case "stopping": return .stopping
            default: return .starting
            }
        }
        switch job.lastExitCode {
        case "75": return .waitingForLock
        case nil, "0", "(never exited)": return .off
        case let code?: return .crashed(exitCode: code)
        }
    }

    public var title: String {
        switch self {
        case .notInstalled: return "Service not installed"
        case .off: return "Off"
        case .starting: return "Starting…"
        case .loading: return "Loading model…"
        case .ready: return "Ready"
        case .idle: return "Idle (model unloaded until the next request)"
        case .reloading: return "Reloading model…"
        case .recovering: return "Recovering (see log)"
        case .stopping: return "Stopping…"
        case .waitingForLock: return "Waiting for another lily process to exit"
        case .crashed(let code): return "Exited with \(code), restarting"
        }
    }

    /// Whether the toggle offers Stop (otherwise Start).
    public var isUp: Bool {
        switch self {
        case .notInstalled, .off, .stopping: return false
        default: return true
        }
    }

    /// SF Symbol for the menu bar button.
    public var symbolName: String {
        switch self {
        case .ready: return "brain.head.profile.fill"
        case .notInstalled, .off, .idle: return "brain.head.profile"
        case .starting, .loading, .reloading, .stopping: return "hourglass"
        case .recovering, .waitingForLock, .crashed: return "exclamationmark.triangle"
        }
    }

    /// Drawn greyed out: nothing is running.
    public var isDimmed: Bool { self == .off || self == .notInstalled }
}
