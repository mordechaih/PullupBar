import XCTest
@testable import LocalDashboard

private struct FakeTokenProvider: KeychainTokenProviding {
    let token: String?
    func fetchOAuthToken() -> String? { token }
}

private struct FakeRunner: ProcessRunning {
    let searchOutput: String?
    func run(_ path: String, _ args: [String]) -> String? {
        if path == "/bin/zsh" { return "/usr/bin/gh" }
        return args.contains("search") ? searchOutput : nil
    }
}

final class DashboardStoreTests: XCTestCase {
    @MainActor
    func testRefreshSessionsPopulatesRowsForLiveSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sessionsDir = root.appendingPathComponent("sessions")
        let projectsDir = root.appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let currentPid = Int(ProcessInfo.processInfo.processIdentifier)
        let cwd = "/tmp/proj"
        let sessionId = "abc"
        try #"{"pid":\#(currentPid),"sessionId":"abc","cwd":"\#(cwd)","name":"proj","status":"busy"}"#
            .write(to: sessionsDir.appendingPathComponent("abc.json"), atomically: true, encoding: .utf8)

        let projDir = projectsDir.appendingPathComponent(encodedProjectDir(forCwd: cwd))
        try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
        try #"{"type":"assistant","message":{"model":"claude-sonnet-5","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":1,"output_tokens":1}}}"#
            .write(to: projDir.appendingPathComponent("\(sessionId).jsonl"), atomically: true, encoding: .utf8)

        let store = DashboardStore(sessionsDir: sessionsDir.path, projectsDir: projectsDir.path)
        await store.refreshSessions()

        XCTAssertEqual(store.sessionRows.count, 1)
        XCTAssertEqual(store.sessionRows.first?.name, "proj")
    }

    @MainActor
    func testRefreshUsageSetsUsageOnSuccess() async {
        let json = #"{"extra_usage":{"used_credits":500,"monthly_limit":2000,"utilization":25.0}}"#
        let dataTask: DataTaskFunc = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (json.data(using: .utf8)!, response)
        }
        let store = DashboardStore(tokenProvider: FakeTokenProvider(token: "tok"), dataTask: dataTask)

        await store.refreshUsage()

        XCTAssertEqual(store.usage?.usedPercent, 25)
        XCTAssertFalse(store.usageUnavailable)
    }

    @MainActor
    func testRefreshUsageMarksUnavailableOnFailure() async {
        let dataTask: DataTaskFunc = { _ in (Data(), URLResponse()) }
        let store = DashboardStore(tokenProvider: FakeTokenProvider(token: nil), dataTask: dataTask)

        await store.refreshUsage()

        XCTAssertTrue(store.usageUnavailable)
    }

    @MainActor
    func testRefreshPullRequestsSetsBadgeCount() async {
        let search = """
        [{"number":1,"title":"a","url":"https://x/1","isDraft":false,"repository":{"nameWithOwner":"o/r"},"createdAt":"2026-06-01T12:00:00Z"},
         {"number":2,"title":"b","url":"https://x/2","isDraft":false,"repository":{"nameWithOwner":"o/r"},"createdAt":"2026-06-01T12:00:00Z"}]
        """
        let store = DashboardStore(processRunner: FakeRunner(searchOutput: search))

        await store.refreshPullRequests()

        XCTAssertEqual(store.pullRequests.count, 2)
        XCTAssertEqual(store.badgeCount, 2)
        XCTAssertFalse(store.prsUnavailable)
    }

    @MainActor
    func testRefreshPullRequestsMarksUnavailableOnFailure() async {
        let store = DashboardStore(processRunner: FakeRunner(searchOutput: nil))

        await store.refreshPullRequests()

        XCTAssertTrue(store.prsUnavailable)
        XCTAssertEqual(store.badgeCount, 0)
    }
}
