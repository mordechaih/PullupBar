import XCTest
@testable import PullupBar

private struct FakeGHRunner: ProcessRunning {
    let searchOutput: String?
    let detailOutputs: [String: String]

    func run(_ path: String, _ args: [String]) -> String? {
        if args == ["-l", "-c", "command -v gh"] { return "/usr/bin/gh" }
        if args.contains("search") { return searchOutput }
        if args.contains("view"), let number = args.first(where: { Int($0) != nil }) {
            return detailOutputs[number]
        }
        return nil
    }
}

/// Records the argument lists of every `gh search` invocation so tests can assert on flags.
private final class SearchCapturingRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _searchArgs: [[String]] = []
    // The two closed-PR searches run concurrently, so guard the recording with a lock.
    var searchArgs: [[String]] {
        lock.lock(); defer { lock.unlock() }
        return _searchArgs
    }

    func run(_ path: String, _ args: [String]) -> String? {
        if args == ["-l", "-c", "command -v gh"] { return "/usr/bin/gh" }
        if args.contains("search") {
            lock.lock()
            _searchArgs.append(args)
            lock.unlock()
            return "[]"
        }
        return nil
    }
}

final class PullRequestFetcherTests: XCTestCase {
    func testFetchPullRequestsEnrichesEachResult() {
        let search = """
        [{"number":10,"title":"Fix bug","url":"https://x/10","isDraft":false,"repository":{"nameWithOwner":"o/r"},"createdAt":"2026-06-01T12:00:00Z"}]
        """
        let detail = #"{"statusCheckRollup":[{"conclusion":"SUCCESS","state":null}],"reviewDecision":"APPROVED","mergeable":"MERGEABLE"}"#
        let runner = FakeGHRunner(searchOutput: search, detailOutputs: ["10": detail])

        let result = fetchPullRequests(runner: runner)

        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?[0].ciStatus, "SUCCESS")
        XCTAssertEqual(result?[0].reviewDecision, "APPROVED")
    }

    func testReturnsNilWhenSearchFails() {
        let runner = FakeGHRunner(searchOutput: nil, detailOutputs: [:])
        XCTAssertNil(fetchPullRequests(runner: runner))
    }

    func testKeepsUnenrichedRowWhenDetailCallFails() {
        let search = """
        [{"number":11,"title":"No detail","url":"https://x/11","isDraft":false,"repository":{"nameWithOwner":"o/r"},"createdAt":"2026-06-01T12:00:00Z"}]
        """
        let runner = FakeGHRunner(searchOutput: search, detailOutputs: [:])

        let result = fetchPullRequests(runner: runner)

        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?[0].ciStatus, "PENDING")
    }

    func testEmptySearchResultsReturnsEmptyArray() {
        let runner = FakeGHRunner(searchOutput: "[]", detailOutputs: [:])
        XCTAssertEqual(fetchPullRequests(runner: runner)?.count, 0)
    }

    func testClosedFetchUsesConfiguredLimit() {
        let runner = SearchCapturingRunner()
        _ = fetchPullRequests(runner: runner, state: .closed, closedLimit: 5)

        XCTAssertFalse(runner.searchArgs.isEmpty)
        XCTAssertTrue(runner.searchArgs.allSatisfy { args in
            guard let index = args.firstIndex(of: "--limit"), index + 1 < args.count else { return false }
            return args[index + 1] == "5"
        })
    }

    func testResolveGHExecutablePathPrefersLoginShellLookup() {
        struct EchoPathRunner: ProcessRunning {
            func run(_ path: String, _ args: [String]) -> String? {
                guard args == ["-l", "-c", "command -v gh"] else { return nil }
                return "/opt/homebrew/bin/gh\n"
            }
        }
        // fileExists returns true for a different path — the shell result must still win.
        let resolved = resolveGHExecutablePath(
            runner: EchoPathRunner(),
            shellPath: "/bin/zsh",
            fileExists: { $0 == "/usr/local/bin/gh" }
        )
        XCTAssertEqual(resolved, "/opt/homebrew/bin/gh")
    }

    func testResolveGHExecutablePathFallsBackToCommonInstallPath() {
        struct NoShellGHRunner: ProcessRunning {
            func run(_ path: String, _ args: [String]) -> String? { "" }
        }
        let resolved = resolveGHExecutablePath(
            runner: NoShellGHRunner(),
            shellPath: "/bin/zsh",
            fileExists: { $0 == "/opt/homebrew/bin/gh" }
        )
        XCTAssertEqual(resolved, "/opt/homebrew/bin/gh")
    }

    func testResolveGHExecutablePathReturnsNilWhenNotFound() {
        struct EmptyRunner: ProcessRunning {
            func run(_ path: String, _ args: [String]) -> String? { "" }
        }
        let resolved = resolveGHExecutablePath(
            runner: EmptyRunner(),
            shellPath: "/bin/zsh",
            fileExists: { _ in false }
        )
        XCTAssertNil(resolved)
    }
}
