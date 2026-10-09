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

/// Records every call, failing (returning nil) for executables listed in `failing`.
private final class RecordingRunner: ProcessRunning, @unchecked Sendable {
    var calls: [(path: String, args: [String])] = []
    let failing: Set<String>
    init(failing: Set<String> = []) { self.failing = failing }
    func run(_ path: String, _ args: [String]) -> String? {
        calls.append((path, args)); return failing.contains(path) ? nil : "ok"
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
        let script = prDraftScriptContents(dir: "/clones/r", branch: "feature", prompt: "do it", agent: .claude)
        XCTAssertTrue(script.contains("cd '/clones/r'"))
        XCTAssertTrue(script.contains("git checkout 'feature'"))
        XCTAssertTrue(script.contains("claude 'do it'"))
    }

    func testScriptContentsEscapesShellMetacharacters() {
        let script = prDraftScriptContents(dir: "/clones/r", branch: "x\";touch pwn;echo\"y", prompt: "p", agent: .claude)
        // The whole branch name stays inside single quotes, so `;touch pwn` is literal, not executed.
        XCTAssertTrue(script.contains("git checkout 'x\";touch pwn;echo\"y'"))
    }

    func testScriptContentsEscapesEmbeddedSingleQuote() {
        let script = prDraftScriptContents(dir: "/clones/r", branch: "it's; echo pwn", prompt: "p", agent: .claude)
        // The embedded single quote is closed/escaped/reopened as '\'' so the whole name stays one
        // literal argument and `; echo pwn` never executes.
        XCTAssertTrue(script.contains("git checkout 'it'\\''s; echo pwn'"))
    }

    func testLaunchPRDraftOpensScriptWithChosenApp() {
        let runner = ArgCapturingRunner()
        var writtenTo: String?
        let ok = launchPRDraftSession(
            sampleBranch, agent: .claude, destination: .terminal(appPath: "/Applications/iTerm.app"), runner: runner,
            writeScript: { _ in writtenTo = "/tmp/x.command"; return "/tmp/x.command" }
        )
        XCTAssertTrue(ok)
        XCTAssertEqual(writtenTo, "/tmp/x.command")
        XCTAssertEqual(runner.lastPath, "/usr/bin/open")
        XCTAssertEqual(runner.lastArgs, ["-a", "/Applications/iTerm.app", "/tmp/x.command"])
    }

    func testLaunchPRDraftUsesDefaultHandlerWhenNoApp() {
        let runner = ArgCapturingRunner()
        let ok = launchPRDraftSession(
            sampleBranch, agent: .claude, destination: .terminal(appPath: ""), runner: runner,
            writeScript: { _ in "/tmp/x.command" }
        )
        XCTAssertTrue(ok)
        XCTAssertEqual(runner.lastPath, "/usr/bin/open")
        XCTAssertEqual(runner.lastArgs, ["/tmp/x.command"])
    }

    func testLaunchFailsWhenScriptCannotBeWritten() {
        let runner = ArgCapturingRunner()
        let ok = launchPRDraftSession(
            sampleBranch, agent: .claude, destination: .terminal(appPath: ""), runner: runner,
            writeScript: { _ in nil }
        )
        XCTAssertFalse(ok)
        XCTAssertNil(runner.lastArgs)
    }

    func testClaudeSessionScriptCdsAndRunsBareClaude() {
        let script = agentSessionScriptContents(dir: "/clones/r", agent: .claude)
        XCTAssertTrue(script.contains("cd '/clones/r'"))
        XCTAssertTrue(script.contains("&& claude"))
        // A bare session opens interactively — no branch checkout and no prompt.
        XCTAssertFalse(script.contains("git checkout"))
    }

    func testClaudeSessionScriptQuotesDir() {
        let script = agentSessionScriptContents(dir: "/weird'; touch pwn", agent: .claude)
        XCTAssertTrue(script.contains("cd '/weird'\\''; touch pwn'"))
    }

    func testLaunchClaudeSessionOpensScriptWithChosenApp() {
        let runner = ArgCapturingRunner()
        let ok = launchAgentSession(
            dir: "/clones/r", agent: .claude, destination: .terminal(appPath: "/Applications/Ghostty.app"), runner: runner,
            writeScript: { _ in "/tmp/x.command" }
        )
        XCTAssertTrue(ok)
        XCTAssertEqual(runner.lastPath, "/usr/bin/open")
        XCTAssertEqual(runner.lastArgs, ["-a", "/Applications/Ghostty.app", "/tmp/x.command"])
    }

    func testLaunchClaudeSessionUsesDefaultHandlerWhenNoApp() {
        let runner = ArgCapturingRunner()
        let ok = launchAgentSession(dir: "/clones/r", agent: .claude, destination: .terminal(appPath: ""), runner: runner, writeScript: { _ in "/tmp/x.command" })
        XCTAssertTrue(ok)
        XCTAssertEqual(runner.lastArgs, ["/tmp/x.command"])
    }

    func testLaunchClaudeSessionFailsWhenScriptCannotBeWritten() {
        let runner = ArgCapturingRunner()
        let ok = launchAgentSession(dir: "/clones/r", agent: .claude, destination: .terminal(appPath: ""), runner: runner, writeScript: { _ in nil })
        XCTAssertFalse(ok)
        XCTAssertNil(runner.lastArgs)
    }

    func testLaunchClaudeSessionInDesktopAppOpensDeepLinkWithoutScript() {
        let runner = ArgCapturingRunner()
        var wroteScript = false
        let ok = launchAgentSession(
            dir: "/clones/r", agent: .claude, destination: .desktopApp, runner: runner,
            writeScript: { _ in wroteScript = true; return "/tmp/x.command" }
        )
        XCTAssertTrue(ok)
        XCTAssertFalse(wroteScript)
        XCTAssertEqual(runner.lastPath, "/usr/bin/open")
        XCTAssertEqual(runner.lastArgs, ["claude://code/new?folder=%2Fclones%2Fr"])
    }

    func testLaunchPRDraftInDesktopAppChecksOutThenOpensDeepLinkWithPrompt() {
        let runner = RecordingRunner()
        let ok = launchPRDraftSession(sampleBranch, agent: .claude, destination: .desktopApp, runner: runner, writeScript: { _ in nil })
        XCTAssertTrue(ok)
        XCTAssertEqual(runner.calls.map(\.path), ["/usr/bin/git", "/usr/bin/open"])
        XCTAssertEqual(runner.calls[0].args, ["-C", "/clones/r", "checkout", "feature"])
        XCTAssertEqual(runner.calls[1].args, [claudeDesktopSessionURL(dir: "/clones/r", prompt: prDraftPrompt)])
    }

    func testLaunchPRDraftInDesktopAppSkipsOpenWhenCheckoutFails() {
        let runner = RecordingRunner(failing: ["/usr/bin/git"])
        let ok = launchPRDraftSession(sampleBranch, agent: .claude, destination: .desktopApp, runner: runner, writeScript: { _ in nil })
        XCTAssertFalse(ok)
        XCTAssertEqual(runner.calls.map(\.path), ["/usr/bin/git"])
    }

    func testCursorPRDraftScriptGuardsMissingCLIThenRunsAgent() {
        let script = prDraftScriptContents(dir: "/clones/r", branch: "feature", prompt: "do it", agent: .cursor)
        XCTAssertTrue(script.contains("command -v agent"))
        XCTAssertTrue(script.contains("curl https://cursor.com/install -fsS | bash"))
        XCTAssertTrue(script.contains("cd '/clones/r' && git checkout 'feature' && agent 'do it'"))
        XCTAssertFalse(script.contains("claude"))
    }

    func testClaudeScriptHasNoCLIGuard() {
        XCTAssertFalse(prDraftScriptContents(dir: "/r", branch: "b", prompt: "p", agent: .claude).contains("command -v"))
    }

    func testCursorSessionScriptRunsBareAgent() {
        let script = agentSessionScriptContents(dir: "/clones/r", agent: .cursor)
        XCTAssertTrue(script.contains("cd '/clones/r' && agent"))
        XCTAssertFalse(script.contains("git checkout"))
    }

    func testLaunchPRDraftCursorInTerminalOpensAgentScript() {
        let runner = ArgCapturingRunner()
        var written: String?
        let ok = launchPRDraftSession(
            sampleBranch, agent: .cursor, destination: .terminal(appPath: "/Applications/Ghostty.app"), runner: runner,
            writeScript: { written = $0; return "/tmp/x.command" }
        )
        XCTAssertTrue(ok)
        XCTAssertTrue(written?.contains("&& agent 'Review this branch") == true)
        XCTAssertEqual(runner.lastArgs, ["-a", "/Applications/Ghostty.app", "/tmp/x.command"])
    }

    func testLaunchPRDraftCursorInDesktopAppChecksOutOpensFolderWaitsThenSendsPrompt() {
        let runner = RecordingRunner()
        let ok = launchPRDraftSession(
            sampleBranch, agent: .cursor, destination: .desktopApp, runner: runner,
            writeScript: { _ in nil }, waitForApp: { _ in runner.calls.append(("wait", [])) }
        )
        XCTAssertTrue(ok)
        XCTAssertEqual(runner.calls.map(\.path), ["/usr/bin/git", "/usr/bin/open", "wait", "/usr/bin/open"])
        XCTAssertEqual(runner.calls[1].args, ["-b", "com.todesktop.230313mzl4w4u92", "/clones/r"])
        XCTAssertEqual(runner.calls[3].args, [cursorPromptURL(prompt: prDraftPrompt)])
    }

    func testLaunchCursorSessionInDesktopAppOpensFolderWithoutWaiting() {
        let runner = RecordingRunner()
        var waited = false
        let ok = launchAgentSession(
            dir: "/clones/r", agent: .cursor, destination: .desktopApp, runner: runner,
            writeScript: { _ in nil }, waitForApp: { _ in waited = true }
        )
        XCTAssertTrue(ok)
        XCTAssertFalse(waited)
        XCTAssertEqual(runner.calls.map(\.args), [["-b", "com.todesktop.230313mzl4w4u92", "/clones/r"]])
    }

    func testLaunchPRDraftCursorInDesktopAppStopsWhenCheckoutFails() {
        let runner = RecordingRunner(failing: ["/usr/bin/git"])
        var waited = false
        let ok = launchPRDraftSession(
            sampleBranch, agent: .cursor, destination: .desktopApp, runner: runner,
            writeScript: { _ in nil }, waitForApp: { _ in waited = true }
        )
        XCTAssertFalse(ok)
        XCTAssertFalse(waited)
        XCTAssertEqual(runner.calls.map(\.path), ["/usr/bin/git"])
    }

    func testLaunchPRDraftCursorInDesktopAppSkipsPromptWhenFolderFailsToOpen() {
        let runner = RecordingRunner(failing: ["/usr/bin/open"])
        var waited = false
        let ok = launchPRDraftSession(
            sampleBranch, agent: .cursor, destination: .desktopApp, runner: runner,
            writeScript: { _ in nil }, waitForApp: { _ in waited = true }
        )
        XCTAssertFalse(ok)
        XCTAssertFalse(waited)
        XCTAssertEqual(runner.calls.map(\.path), ["/usr/bin/git", "/usr/bin/open"])
    }
}
