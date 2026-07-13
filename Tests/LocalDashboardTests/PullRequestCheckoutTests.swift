import XCTest
@testable import LocalDashboard

private struct FakeCheckoutRunner: ProcessRunning {
    let ghPath: String?
    var lastCheckoutArgs: [String]?
    var lastCwd: String?
    let checkoutSucceeds: Bool

    func run(_ path: String, _ args: [String]) -> String? {
        if path == "/bin/zsh" { return ghPath }
        return nil
    }

    func run(_ path: String, _ args: [String], cwd: String) -> String? {
        checkoutSucceeds ? "done" : nil
    }
}

final class PullRequestCheckoutTests: XCTestCase {
    func testLocalRepoDirectoryFindsExistingClone() {
        let dir = localRepoDirectory(
            forRepo: "mordechaih/localdashboard",
            searchRoot: "/Users/example/GitHub",
            fileExists: { $0 == "/Users/example/GitHub/localdashboard/.git" }
        )
        XCTAssertEqual(dir, "/Users/example/GitHub/localdashboard")
    }

    func testLocalRepoDirectoryReturnsNilWhenNoCloneFound() {
        let dir = localRepoDirectory(
            forRepo: "mordechaih/localdashboard",
            searchRoot: "/Users/example/GitHub",
            fileExists: { _ in false }
        )
        XCTAssertNil(dir)
    }

    func testCheckoutPullRequestBranchSucceedsWhenRepoDirProvided() {
        let runner = FakeCheckoutRunner(ghPath: "/usr/bin/gh", checkoutSucceeds: true)
        let result = checkoutPullRequestBranch(repo: "o/r", number: 5, runner: runner, localRepoDir: "/tmp/r")
        XCTAssertTrue(result)
    }

    func testCheckoutPullRequestBranchFailsWhenGHUnresolved() {
        let runner = FakeCheckoutRunner(ghPath: nil, checkoutSucceeds: true)
        let result = checkoutPullRequestBranch(repo: "o/r", number: 5, runner: runner, localRepoDir: "/tmp/r")
        XCTAssertFalse(result)
    }

    func testCheckoutPullRequestBranchFailsWhenNoLocalRepoDir() {
        let runner = FakeCheckoutRunner(ghPath: "/usr/bin/gh", checkoutSucceeds: true)
        let result = checkoutPullRequestBranch(
            repo: "o/definitely-not-a-real-cloned-repo-\(UUID().uuidString)",
            number: 5,
            runner: runner,
            localRepoDir: nil
        )
        XCTAssertFalse(result)
    }
}
