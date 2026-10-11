import Foundation

/// `GET /health`. lily answers 503 while loading or stopping, with the same body.
public struct Health: Decodable, Equatable, Sendable {
    public var status: String
    /// `loading`, `ready`, `idle`, `reloading`, `recovering` or `stopping`.
    public var state: String
    public var model: String?
    public var idleUnloadSecs: Int?

    public init(status: String = "ok", state: String, model: String? = nil, idleUnloadSecs: Int? = nil) {
        self.status = status
        self.state = state
        self.model = model
        self.idleUnloadSecs = idleUnloadSecs
    }
}

/// The part of a request's `timings` object the menu shows.
public struct RequestTimings: Decodable, Equatable, Sendable {
    public var promptTokens: Int
    public var cachedTokens: Int
    public var generatedTokens: Int
    public var prefillPerSecond: Double
    public var decodePerSecond: Double
}

/// One entry of `GET /v1/timings`.
public struct TimingsEntry: Decodable, Equatable, Sendable {
    public var id: String
    /// Unix seconds.
    public var created: Int
    public var timings: RequestTimings

    public var createdDate: Date { Date(timeIntervalSince1970: TimeInterval(created)) }
}

/// `GET /v1/timings`: the most recent requests, newest first.
public struct TimingsList: Decodable, Sendable {
    public var data: [TimingsEntry]
    public var latest: TimingsEntry? { data.first }
}

public enum ServerAPI {
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }

    /// GETs `path` and decodes the body whatever the status code; nil when the
    /// server does not answer in time or the body is not what was expected.
    public static func get<T: Decodable & Sendable>(_ type: T.Type, _ path: String, from base: URL, timeout: TimeInterval = 1.5) async -> T? {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.timeoutInterval = timeout
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return try? decode(type, from: data)
    }
}
