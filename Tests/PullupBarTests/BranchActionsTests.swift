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

    func testScriptContentsEscapesEmbeddedSingleQuote() {
        let script = prDraftScriptContents(dir: "/clones/r", branch: "it's; echo pwn", prompt: "p")
        // The embedded single quote is closed/escaped/reopened as '\'' so the whole name stays one
        // literal argument and `; echo pwn` never executes.
        XCTAssertTrue(script.contains("git checkout 'it'\\''s; echo pwn'"))
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

    func testClaudeSessionScriptCdsAndRunsBareClaude() {
        let script = claudeSessionScriptContents(dir: "/clones/r")
        XCTAssertTrue(script.contains("cd '/clones/r'"))
        XCTAssertTrue(script.contains("&& claude"))
        // A bare session opens interactively — no branch checkout and no prompt.
        XCTAssertFalse(script.contains("git checkout"))
    }

    func testClaudeSessionScriptQuotesDir() {
        let script = claudeSessionScriptContents(dir: "/weird'; touch pwn")
        XCTAssertTrue(script.contains("cd '/weird'\\''; touch pwn'"))
    }

    func testLaunchClaudeSessionSubstitutesScriptPathAndRunsViaSh() {
        let runner = ArgCapturingRunner()
        let ok = launchClaudeSession(
            dir: "/clones/r", command: "open -a iTerm {script}", runner: runner,
            writeScript: { _ in "/tmp/x.command" }
        )
        XCTAssertTrue(ok)
        XCTAssertEqual(runner.lastPath, "/bin/sh")
        XCTAssertEqual(runner.lastArgs, ["-c", "open -a iTerm /tmp/x.command"])
    }

    func testLaunchClaudeSessionFailsWhenScriptCannotBeWritten() {
        let runner = ArgCapturingRunner()
        let ok = launchClaudeSession(dir: "/clones/r", command: "open {script}", runner: runner, writeScript: { _ in nil })
        XCTAssertFalse(ok)
        XCTAssertNil(runner.lastArgs)
    }
}
