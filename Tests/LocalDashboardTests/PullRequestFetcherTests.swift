import XCTest
@testable import LocalDashboard

private struct FakeGHRunner: ProcessRunning {
    let searchOutput: String?
    let detailOutputs: [String: String]

    func run(_ path: String, _ args: [String]) -> String? {
        if path == "/bin/zsh" { return "/usr/bin/gh" }
        if args.contains("search") { return searchOutput }
        if args.contains("view"), let number = args.first(where: { Int($0) != nil }) {
            return detailOutputs[number]
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

    func testReturnsNilWhenGHCannotBeResolved() {
        struct NoGHRunner: ProcessRunning {
            func run(_ path: String, _ args: [String]) -> String? {
                path == "/bin/zsh" ? "" : nil
            }
        }
        XCTAssertNil(fetchPullRequests(runner: NoGHRunner()))
    }

    func testResolveGHExecutablePathUsesLoginShellLookup() {
        struct EchoPathRunner: ProcessRunning {
            func run(_ path: String, _ args: [String]) -> String? {
                guard path == "/bin/zsh", args == ["-l", "-c", "command -v gh"] else { return nil }
                return "/opt/homebrew/bin/gh\n"
            }
        }
        XCTAssertEqual(resolveGHExecutablePath(runner: EchoPathRunner()), "/opt/homebrew/bin/gh")
    }

    func testResolveGHExecutablePathReturnsNilWhenNotFound() {
        struct EmptyRunner: ProcessRunning {
            func run(_ path: String, _ args: [String]) -> String? { "" }
        }
        XCTAssertNil(resolveGHExecutablePath(runner: EmptyRunner()))
    }
}
