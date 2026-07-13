import XCTest
@testable import PullupBar

/// Answers git/gh calls from canned tables keyed by the distinctive argument.
private struct FakeBranchRunner: ProcessRunning {
    var email: String = "me@x.com"
    var originByDir: [String: String] = [:]        // dir -> origin URL
    var defaultBranchByDir: [String: String] = [:] // dir -> "origin/main"
    var localRefsByDir: [String: String] = [:]     // dir -> for-each-ref refs/heads output
    var remoteRefsByDir: [String: String] = [:]    // dir -> for-each-ref refs/remotes/origin output
    var prListByHead: [String: String] = [:]       // branch -> gh pr list json

    func run(_ path: String, _ args: [String]) -> String? {
        if args == ["-l", "-c", "command -v gh"] { return "/usr/bin/gh" }
        if args == ["config", "--get", "user.email"] { return email }
        if let ci = args.firstIndex(of: "-C"), ci + 1 < args.count {
            let dir = args[ci + 1]
            if args.contains("remote") { return originByDir[dir] }
            if args.contains("symbolic-ref") { return defaultBranchByDir[dir] }
            if args.contains("for-each-ref") {
                return args.contains("refs/heads") ? localRefsByDir[dir] : remoteRefsByDir[dir]
            }
        }
        if args.first == "pr", args.contains("list"), let hi = args.firstIndex(of: "--head"), hi + 1 < args.count {
            return prListByHead[args[hi + 1]] ?? "[]"
        }
        return nil
    }
}

final class BranchFetcherTests: XCTestCase {
    func testDiscoverClonesReadsOriginPerSubdir() {
        var runner = FakeBranchRunner()
        runner.originByDir = ["/root/a": "git@github.com:o/a.git", "/root/b": "not-a-repo"]
        let clones = discoverClones(
            roots: ["/root"], runner: runner,
            subdirectories: { _ in ["/root/a", "/root/b"] }
        )
        XCTAssertEqual(clones.map(\.repo), ["o/a"])
        XCTAssertEqual(clones.first?.dir, "/root/a")
    }

    func testFetchKeepsLocalBranchWithoutPRAndDropsDefaultAndPRBranches() {
        var runner = FakeBranchRunner()
        runner.originByDir = ["/root/a": "git@github.com:o/a.git"]
        runner.defaultBranchByDir = ["/root/a": "origin/main"]
        runner.localRefsByDir = ["/root/a": "main\t<me@x.com>\t100\nfeature\t<me@x.com>\t200\nhas-pr\t<me@x.com>\t150\n"]
        runner.remoteRefsByDir = ["/root/a": ""]
        runner.prListByHead = ["has-pr": #"[{"number":7}]"#, "feature": "[]"]

        let result = fetchBranchesWithoutPR(
            runner: runner, roots: ["/root"],
            subdirectories: { _ in ["/root/a"] }
        )

        XCTAssertEqual(result?.map(\.name), ["feature"])
        XCTAssertEqual(result?.first?.hasLocal, true)
        XCTAssertEqual(result?.first?.repo, "o/a")
    }

    func testFetchFiltersRemoteBranchesByAuthorEmail() {
        var runner = FakeBranchRunner(email: "me@x.com")
        runner.originByDir = ["/root/a": "git@github.com:o/a.git"]
        runner.defaultBranchByDir = ["/root/a": "origin/main"]
        runner.localRefsByDir = ["/root/a": ""]
        runner.remoteRefsByDir = ["/root/a":
            "mine\t<me@x.com>\t300\ntheirs\t<other@x.com>\t400\nHEAD\t<me@x.com>\t500\n"]

        let result = fetchBranchesWithoutPR(
            runner: runner, roots: ["/root"],
            subdirectories: { _ in ["/root/a"] }
        )

        XCTAssertEqual(result?.map(\.name), ["mine"])  // theirs filtered by email, HEAD skipped
        XCTAssertEqual(result?.first?.hasRemote, true)
    }

    func testFetchSortsByTipDateDescending() {
        var runner = FakeBranchRunner()
        runner.originByDir = ["/root/a": "git@github.com:o/a.git"]
        runner.defaultBranchByDir = ["/root/a": "origin/main"]
        runner.localRefsByDir = ["/root/a": "old\t<me@x.com>\t100\nnew\t<me@x.com>\t900\n"]
        runner.remoteRefsByDir = ["/root/a": ""]

        let result = fetchBranchesWithoutPR(
            runner: runner, roots: ["/root"],
            subdirectories: { _ in ["/root/a"] }
        )
        XCTAssertEqual(result?.map(\.name), ["new", "old"])
    }

    func testFetchReturnsNilWhenGHUnavailable() {
        struct NoGH: ProcessRunning { func run(_ p: String, _ a: [String]) -> String? { "" } }
        let result = fetchBranchesWithoutPR(
            runner: NoGH(), roots: ["/root"],
            subdirectories: { _ in ["/root/a"] },
            fileExists: { _ in false }
        )
        XCTAssertNil(result)
    }
}
