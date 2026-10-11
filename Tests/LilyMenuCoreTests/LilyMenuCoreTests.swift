import Foundation
import Testing
@testable import LilyMenuCore

// MARK: launchctl print

/// Trimmed from a real `launchctl print gui/501/com.lily.server`.
private let runningJob = """
gui/501/com.lily.server = {
\tactive count = 1
\tpath = /Users/me/Library/LaunchAgents/com.lily.server.plist
\ttype = LaunchAgent
\tstate = running

\tprogram = /Users/me/lily/target/release/lily
\targuments = {
\t\t/Users/me/lily/target/release/lily
\t\t--bind
\t\t127.0.0.1:8000
\t}

\tenvironment = {
\t\tpid = 999
\t\tXPC_SERVICE_NAME => com.lily.server
\t}

\truns = 1
\tpid = 31632
\timmediate reason = speculative
\tlast exit code = (never exited)
}
"""

@Test func parsesTopLevelPidAndExitCode() {
    #expect(LaunchdJob(launchctlPrint: runningJob) == LaunchdJob(pid: 31632, lastExitCode: "(never exited)"))
}

@Test func nestedLinesDoNotCount() {
    let text = "gui/501/x = {\n\tenvironment = {\n\t\tpid = 7\n\t}\n\tlast exit code = 75\n}\n"
    #expect(LaunchdJob(launchctlPrint: text) == LaunchdJob(pid: nil, lastExitCode: "75"))
}

// MARK: Plist

@Test func readsBindLogAndModelFromPlist() {
    let config = ServiceConfig(plist: [
        "ProgramArguments": ["/bin/lily", "--model", "/m/q4-xl", "--bind=0.0.0.0:9001"],
        "StandardErrorPath": "/logs/server.log",
    ])
    #expect(config == ServiceConfig(bind: "0.0.0.0:9001", logPath: "/logs/server.log", modelPath: "/m/q4-xl"))
}

@Test func missingBindFallsBackToLilyDefault() {
    #expect(ServiceConfig(plist: ["ProgramArguments": ["/bin/lily", "--bind"]]).bind == "127.0.0.1:8000")
}

@Test func loadReturnsNilWithoutPlist() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("absent-\(UUID()).plist")
    #expect(try ServiceConfig.load(from: url) == nil)
}

@Test func loadReadsAWrittenPlist() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("lily-\(UUID()).plist")
    defer { try? FileManager.default.removeItem(at: url) }
    let plist: [String: Any] = ["ProgramArguments": ["/bin/lily", "--bind", "127.0.0.1:8123"]]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
    #expect(try ServiceConfig.load(from: url)?.apiBaseURL == "http://127.0.0.1:8123/v1")
}

@Test(arguments: [
    ("127.0.0.1:8000", "http://127.0.0.1:8000/v1"),
    ("0.0.0.0:8000", "http://127.0.0.1:8000/v1"),
    ("localhost:9000", "http://localhost:9000/v1"),
    ("[::]:8000", "http://[::1]:8000/v1"),
    ("[::1]:8080", "http://[::1]:8080/v1"),
])
func connectsToListenAddress(bind: String, expected: String) {
    #expect(ServiceConfig(bind: bind).apiBaseURL == expected)
}

// MARK: Status

@Test func notLoadedIsOffOnlyWhenInstalled() {
    #expect(ServerStatus.derive(installed: false, job: nil, health: nil) == .notInstalled)
    #expect(ServerStatus.derive(installed: true, job: nil, health: nil) == .off)
}

@Test(arguments: [
    ("ready", ServerStatus.ready),
    ("idle", .idle),
    ("loading", .loading),
    ("reloading", .reloading),
    ("recovering", .recovering),
    ("stopping", .stopping),
])
func runningProcessFollowsHealth(state: String, expected: ServerStatus) {
    #expect(ServerStatus.derive(installed: true, job: LaunchdJob(pid: 1), health: Health(state: state)) == expected)
}

@Test func runningWithoutHealthIsStarting() {
    #expect(ServerStatus.derive(installed: true, job: LaunchdJob(pid: 1), health: nil) == .starting)
}

@Test(arguments: [
    ("0", ServerStatus.off),
    ("(never exited)", .off),
    ("75", .waitingForLock),
    ("1", .crashed(exitCode: "1")),
])
func loadedWithoutProcessFollowsExitCode(code: String, expected: ServerStatus) {
    #expect(ServerStatus.derive(installed: true, job: LaunchdJob(pid: nil, lastExitCode: code), health: nil) == expected)
}

@Test func stopIsOfferedWheneverSomethingRunsOrRetries() {
    #expect(ServerStatus.crashed(exitCode: "1").isUp)
    #expect(ServerStatus.waitingForLock.isUp)
    #expect(!ServerStatus.off.isUp)
    #expect(!ServerStatus.stopping.isUp)
}

// MARK: Server API

@Test func decodesHealthWhileLoading() throws {
    let body = #"{"status":"loading","state":"loading","model":"Qwen3.8-Flash-Next","idle_unload_secs":1800}"#
    let health = try ServerAPI.decode(Health.self, from: Data(body.utf8))
    #expect(health == Health(status: "loading", state: "loading", model: "Qwen3.8-Flash-Next", idleUnloadSecs: 1800))
}

@Test func latestTimingsIsTheFirstEntry() throws {
    // Shape of a real response, with most of lily's extra fields elided.
    let body = """
    {"object":"list","data":[
     {"id":"chatcmpl-2","model":"Qwen3.8-Flash-Next","created":1791680369,"timings":{"prompt_tokens":43,"cached_tokens":0,
      "prefill_tokens":43,"prefill_ms":184.1,"prefill_per_second":233.51,"generated_tokens":31,"decode_ms":288.3,
      "decode_per_second":107.49,"acceptance_ratio":0.86,"pinned":true,"prefill_phases":{"chunks":1}}},
     {"id":"chatcmpl-1","model":"Qwen3.8-Flash-Next","created":1791680000,"timings":{"prompt_tokens":10,"cached_tokens":5,
      "prefill_per_second":1.0,"generated_tokens":1,"decode_per_second":1.0}}
    ]}
    """
    let latest = try ServerAPI.decode(TimingsList.self, from: Data(body.utf8)).latest
    #expect(latest?.id == "chatcmpl-2")
    #expect(latest?.timings == RequestTimings(promptTokens: 43, cachedTokens: 0, generatedTokens: 31,
                                              prefillPerSecond: 233.51, decodePerSecond: 107.49))
}
