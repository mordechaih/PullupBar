import XCTest
@testable import PullupBar

private struct FakeRunner: ProcessRunning {
    let searchOutput: String?
    func run(_ path: String, _ args: [String]) -> String? {
        if args == ["-l", "-c", "command -v gh"] { return "/usr/bin/gh" }
        return args.contains("search") ? searchOutput : nil
    }
}

/// Distinguishes the two closed searches (merged vs. is:unmerged) and the open search.
private struct FakeStateRunner: ProcessRunning {
    var openOutput: String? = "[]"
    var mergedOutput: String? = "[]"
    var unmergedOutput: String? = "[]"

    func run(_ path: String, _ args: [String]) -> String? {
        if args == ["-l", "-c", "command -v gh"] { return "/usr/bin/gh" }
        guard args.contains("search") else { return nil }
        if args.contains("--merged") { return mergedOutput }
        if args.contains("is:unmerged") { return unmergedOutput }
        return openOutput
    }
}

private func prJSON(_ number: Int, closedAt: String? = nil) -> String {
    let closed = closedAt.map { ",\"closedAt\":\"\($0)\"" } ?? ""
    return "{\"number\":\(number),\"title\":\"t\",\"url\":\"https://x/\(number)\",\"isDraft\":false,\"repository\":{\"nameWithOwner\":\"o/r\"},\"createdAt\":\"2026-06-01T12:00:00Z\"\(closed)}"
}

/// Answers git/gh calls from canned tables, matching on the git subcommand rather than the
/// (dynamic, temp-dir) `-C` argument. Mirrors `FakeBranchRunner` from BranchFetcherTests.
private struct BranchStoreFakeRunner: ProcessRunning {
    func run(_ path: String, _ args: [String]) -> String? {
        if args == ["-l", "-c", "command -v gh"] { return "/usr/bin/gh" }
        if args == ["config", "--get", "user.email"] { return "me@x.com" }
        if args.contains("remote") { return "git@github.com:o/a.git" }
        if args.contains("symbolic-ref") { return "origin/main" }
        if args.contains("for-each-ref") {
            return args.contains("refs/heads") ? "feature\t<me@x.com>\t200\n" : ""
        }
        if args.first == "pr", args.contains("list") { return "[]" }
        return nil
    }
}

final class DashboardStoreTests: XCTestCase {
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

    @MainActor
    func testRefreshClosedGroupsMergedAndUnmerged() async {
        let runner = FakeStateRunner(
            mergedOutput: "[\(prJSON(1, closedAt: "2026-06-05T09:00:00Z"))]",
            unmergedOutput: "[\(prJSON(2, closedAt: "2026-06-06T09:00:00Z"))]"
        )
        let store = DashboardStore(processRunner: runner)

        await store.refreshClosedPullRequests()

        XCTAssertTrue(store.closedLoaded)
        XCTAssertFalse(store.closedUnavailable)
        XCTAssertEqual(store.closedPullRequests.count, 2)
        // Sorted newest-closed first: #2 (Jun 6) before #1 (Jun 5).
        XCTAssertEqual(store.closedPullRequests.first?.number, 2)
        XCTAssertEqual(store.closedPullRequests.first(where: { $0.number == 1 })?.isMerged, true)
        XCTAssertEqual(store.closedPullRequests.first(where: { $0.number == 2 })?.isMerged, false)
    }

    @MainActor
    func testBadgeStaysOpenCountWhileViewingClosed() async {
        let runner = FakeStateRunner(
            openOutput: "[\(prJSON(1)),\(prJSON(2))]",
            mergedOutput: "[\(prJSON(3, closedAt: "2026-06-05T09:00:00Z"))]",
            unmergedOutput: "[]"
        )
        let store = DashboardStore(processRunner: runner)

        await store.refreshPullRequests()
        store.selectFilter(.closed)
        await store.refreshClosedPullRequests()

        XCTAssertEqual(store.filter, .closed)
        XCTAssertEqual(store.closedPullRequests.count, 1)
        XCTAssertEqual(store.badgeCount, 2)
    }

    @MainActor
    func testRefreshClosedMarksUnavailableWhenBothSearchesFail() async {
        let runner = FakeStateRunner(mergedOutput: nil, unmergedOutput: nil)
        let store = DashboardStore(processRunner: runner)

        await store.refreshClosedPullRequests()

        XCTAssertTrue(store.closedLoaded)
        XCTAssertTrue(store.closedUnavailable)
    }

    @MainActor
    func testRefreshBranchesPopulatesAndMarksLoaded() async {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("pullupbar-branches-\(UUID().uuidString)")
        let cloneGitDir = root.appendingPathComponent("a").appendingPathComponent(".git")
        try! fm.createDirectory(at: cloneGitDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let settings = SettingsStore(defaults: UserDefaults(suiteName: "s-\(UUID().uuidString)")!)
        settings.repoSearchRoots = [root.path]
        let store = DashboardStore(processRunner: BranchStoreFakeRunner(), settings: settings)

        await store.refreshBranches()

        XCTAssertTrue(store.branchesLoaded)
        XCTAssertFalse(store.branchesUnavailable)
        XCTAssertEqual(store.noPRBranches.map(\.name), ["feature"])
    }

    func testCreatePRCommandDefaultsAndPersists() {
        let defaults = UserDefaults(suiteName: "createpr-\(UUID().uuidString)")!
        let a = SettingsStore(defaults: defaults)
        XCTAssertEqual(a.createPRCommand, SettingsStore.defaultCreatePRCommand)
        a.createPRCommand = "open -a iTerm {script}"
        let b = SettingsStore(defaults: defaults)
        XCTAssertEqual(b.createPRCommand, "open -a iTerm {script}")
    }

    func testOpenClaudeOnCheckoutDefaultsFalseAndPersists() {
        let defaults = UserDefaults(suiteName: "claudecheckout-\(UUID().uuidString)")!
        let a = SettingsStore(defaults: defaults)
        XCTAssertFalse(a.openClaudeOnCheckout)
        a.openClaudeOnCheckout = true
        let b = SettingsStore(defaults: defaults)
        XCTAssertTrue(b.openClaudeOnCheckout)
    }
}
