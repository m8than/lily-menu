import Foundation

/// What the installed launchd plist says about the server.
public struct ServiceConfig: Equatable, Sendable {
    /// lily's own default for `--bind`.
    public static let defaultBind = "127.0.0.1:8000"

    public var bind: String
    /// `StandardErrorPath`, where lily writes its log.
    public var logPath: String?
    /// The checkpoint directory passed as `--model`.
    public var modelPath: String?

    public init(bind: String = ServiceConfig.defaultBind, logPath: String? = nil, modelPath: String? = nil) {
        self.bind = bind
        self.logPath = logPath
        self.modelPath = modelPath
    }

    public init(plist: [String: Any]) {
        let args = plist["ProgramArguments"] as? [String] ?? []
        self.init(
            bind: Self.argument("--bind", in: args) ?? Self.defaultBind,
            logPath: plist["StandardErrorPath"] as? String ?? plist["StandardOutPath"] as? String,
            modelPath: Self.argument("--model", in: args)
        )
    }

    /// Reads a plist file; nil when there is none.
    public static func load(from url: URL) throws -> ServiceConfig? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        return ServiceConfig(plist: object as? [String: Any] ?? [:])
    }

    /// The value of `name` in either `--name value` or `--name=value` form.
    static func argument(_ name: String, in args: [String]) -> String? {
        for (i, arg) in args.enumerated() {
            if arg == name, i + 1 < args.count { return args[i + 1] }
            if arg.hasPrefix(name + "=") { return String(arg.dropFirst(name.count + 1)) }
        }
        return nil
    }

    /// Where to connect: a wildcard listen address is reached on loopback.
    public var baseURL: URL {
        var host: Substring
        var port: Substring = "8000"
        if bind.hasPrefix("["), let close = bind.firstIndex(of: "]") {
            host = bind[bind.index(after: bind.startIndex)..<close]
            let rest = bind[bind.index(after: close)...]
            if rest.hasPrefix(":") { port = rest.dropFirst() }
        } else if let colon = bind.lastIndex(of: ":") {
            host = bind[..<colon]
            port = bind[bind.index(after: colon)...]
        } else {
            host = Substring(bind)
        }
        switch host {
        case "", "0.0.0.0": host = "127.0.0.1"
        case "::": host = "::1"
        default: break
        }
        let hostPart = host.contains(":") ? "[\(host)]" : String(host)
        return URL(string: "http://\(hostPart):\(port)")!
    }

    /// The OpenAI-compatible base URL clients are configured with.
    public var apiBaseURL: String { baseURL.absoluteString + "/v1" }
}
