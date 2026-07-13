// Tests/PullupBarTests/BranchActionsTests.swift
import XCTest
@testable import PullupBar

private final class ArgCapturingRunner: ProcessRunning, @unchecked Sendable {
    var lastPath: String?
    var lastArgs: [String]?
    let result: String?
    init(result: String? = "ok") { self.result = result }
    func run(_ path: String, _ args: [String]) -> String? {
        lastPath = path; lastArgs = args; return result
    }
}

private let sampleBranch = BranchInfo(
    id: "o/r@feature", repo: "o/r", name: "feature",
    localCloneDir: "/clones/r", hasLocal: true, hasRemote: false, tipDate: nil
)

final class BranchActionsTests: XCTestCase {
    func testCheckoutBuildsGitCheckoutArgv() {
        let runner = ArgCapturingRunner()
        XCTAssertTrue(checkoutBranchLocally(sampleBranch, runner: runner))
        XCTAssertEqual(runner.lastArgs, ["-C", "/clones/r", "checkout", "feature"])
    }

    func testArchiveBuildsForceDeleteArgv() {
        let runner = ArgCapturingRunner()
        XCTAssertTrue(archiveBranchLocally(sampleBranch, runner: runner))
        XCTAssertEqual(runner.lastArgs, ["-C", "/clones/r", "branch", "-D", "feature"])
    }

    func testArchiveReturnsFalseOnFailure() {
        let runner = ArgCapturingRunner(result: nil)
        XCTAssertFalse(archiveBranchLocally(sampleBranch, runner: runner))
    }

    func testScriptContentsCdChecksOutAndRunsClaude() {
        let script = prDraftScriptContents(dir: "/clones/r", branch: "feature", prompt: "do it")
        XCTAssertTrue(script.contains("cd '/clones/r'"))
        XCTAssertTrue(script.contains("git checkout 'feature'"))
        XCTAssertTrue(script.contains("claude 'do it'"))
    }

    func testScriptContentsEscapesShellMetacharacters() {
        let script = prDraftScriptContents(dir: "/clones/r", branch: "x\";touch pwn;echo\"y", prompt: "p")
        // The whole branch name stays inside single quotes, so `;touch pwn` is literal, not executed.
        XCTAssertTrue(script.contains("git checkout 'x\";touch pwn;echo\"y'"))
    }

    func testLaunchSubstitutesScriptPathAndRunsViaSh() {
        let runner = ArgCapturingRunner()
        var writtenTo: String?
        let ok = launchPRDraftSession(
            sampleBranch, command: "open -a iTerm {script}", runner: runner,
            writeScript: { _ in writtenTo = "/tmp/x.command"; return "/tmp/x.command" }
        )
        XCTAssertTrue(ok)
        XCTAssertEqual(writtenTo, "/tmp/x.command")
        XCTAssertEqual(runner.lastPath, "/bin/sh")
        XCTAssertEqual(runner.lastArgs, ["-c", "open -a iTerm /tmp/x.command"])
    }

    func testLaunchFailsWhenScriptCannotBeWritten() {
        let runner = ArgCapturingRunner()
        let ok = launchPRDraftSession(
            sampleBranch, command: "open {script}", runner: runner,
            writeScript: { _ in nil }
        )
        XCTAssertFalse(ok)
        XCTAssertNil(runner.lastArgs)
    }
}
