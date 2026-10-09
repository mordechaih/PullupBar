import Foundation

private let defaultGitPath = "/usr/bin/git"
private let openPath = "/usr/bin/open"

/// The instruction handed to the agent session opened by the Create-PR action.
let prDraftPrompt = "Review this branch's changes against the default branch and open a pull request with a clear title and description using the gh CLI."

/// Switches the clone to `branch`. For a remote-only branch, `git checkout <name>` creates a local
/// tracking branch from `origin/<name>` automatically.
@discardableResult
func checkoutBranchLocally(_ branch: BranchInfo, runner: ProcessRunning, gitPath: String = defaultGitPath) -> Bool {
    runner.run(gitPath, ["-C", branch.localCloneDir, "checkout", branch.name]) != nil
}

/// Force-deletes the local branch (`-D`). No-PR branches are typically unmerged, so a plain `-d`
/// would refuse; commits remain recoverable via reflog.
@discardableResult
func archiveBranchLocally(_ branch: BranchInfo, runner: ProcessRunning, gitPath: String = defaultGitPath) -> Bool {
    runner.run(gitPath, ["-C", branch.localCloneDir, "branch", "-D", branch.name]) != nil
}

/// Wraps a string in single quotes for safe embedding in a POSIX shell command, escaping any
/// embedded single quote as '\'' so branch/dir names can't inject shell code.
private func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// A `#!/bin/sh` script that runs `command`. For agents PullupBar checks for, a guard first prints
/// how to install a missing CLI instead of leaving a bare "command not found".
private func agentScript(_ agent: CodingAgent, _ command: String) -> String {
    var lines = ["#!/bin/sh"]
    if let install = agent.cliInstallCommand {
        lines += [
            "if ! command -v \(agent.cliCommand) >/dev/null 2>&1; then",
            "  echo \(shellQuote("The \(agent.displayName) CLI isn't installed. Install it with: \(install)"))",
            "  exit 1",
            "fi",
        ]
    }
    lines.append(command)
    return lines.joined(separator: "\n")
}

/// The `.command` script body: enter the clone, check out the branch, then launch the agent's CLI
/// with `prompt`.
func prDraftScriptContents(dir: String, branch: String, prompt: String, agent: CodingAgent) -> String {
    agentScript(agent, "cd \(shellQuote(dir)) && git checkout \(shellQuote(branch)) && \(agent.cliCommand) \(shellQuote(prompt))")
}

/// The `.command` script body for an interactive session in a clone: `cd` in, launch the agent's
/// CLI with no prompt. Used by the "open agent on checkout" setting.
func agentSessionScriptContents(dir: String, agent: CodingAgent) -> String {
    agentScript(agent, "cd \(shellQuote(dir)) && \(agent.cliCommand)")
}

/// Default: write a script to a temp `.command` file and mark it executable.
/// Returns the file path, or nil if writing fails.
private func writeCommandScript(_ contents: String) -> String? {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("pullupbar-\(UUID().uuidString).command")
    do {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    } catch {
        return nil
    }
}

/// Writes `contents` to a temp `.command` script, then opens it in a terminal via `open`. An empty
/// `appPath` uses the system default handler (`open <script>`, i.e. Terminal); otherwise the app at
/// `appPath` is used (`open -a <appPath> <script>`). No shell is involved, so app paths with spaces
/// are safe. `writeScript` is injected for tests.
@discardableResult
private func launchScript(
    _ contents: String,
    appPath: String,
    runner: ProcessRunning,
    writeScript: (String) -> String?
) -> Bool {
    guard let scriptPath = writeScript(contents) else { return false }
    let args = appPath.isEmpty ? [scriptPath] : ["-a", appPath, scriptPath]
    return runner.run(openPath, args) != nil
}

/// Opens `dir` in `agent`'s desktop app, with `prompt` filled in when given. Claude takes both in
/// one deep link. Cursor's prompt link has no folder parameter, so the folder opens first, then
/// after `waitForApp` the prompt link lands in that window.
private func openInDesktopApp(
    _ agent: CodingAgent,
    dir: String,
    prompt: String?,
    runner: ProcessRunning,
    waitForApp: (CodingAgent) -> Void
) -> Bool {
    switch agent {
    case .claude:
        return runner.run(openPath, [claudeDesktopSessionURL(dir: dir, prompt: prompt)]) != nil
    case .cursor:
        guard runner.run(openPath, ["-b", agent.desktopAppBundleID, dir]) != nil else { return false }
        guard let prompt else { return true }
        waitForApp(agent)
        return runner.run(openPath, [cursorPromptURL(prompt: prompt)]) != nil
    }
}

/// Checks out `branch` and launches `agent` with the PR-draft prompt. In a terminal, the checkout
/// runs inside the script; for a desktop app, PullupBar checks out first and only opens the app if
/// that succeeds, matching the script's `&&`.
@discardableResult
func launchPRDraftSession(
    _ branch: BranchInfo,
    agent: CodingAgent,
    destination: AgentDestination,
    runner: ProcessRunning,
    writeScript: (String) -> String? = writeCommandScript,
    waitForApp: (CodingAgent) -> Void = waitForDesktopApp
) -> Bool {
    switch destination {
    case .terminal(let appPath):
        return launchScript(
            prDraftScriptContents(dir: branch.localCloneDir, branch: branch.name, prompt: prDraftPrompt, agent: agent),
            appPath: appPath, runner: runner, writeScript: writeScript
        )
    case .desktopApp:
        guard checkoutBranchLocally(branch, runner: runner) else { return false }
        return openInDesktopApp(agent, dir: branch.localCloneDir, prompt: prDraftPrompt, runner: runner, waitForApp: waitForApp)
    }
}

/// Opens an interactive `agent` session in `dir` (no prompt). Used after a checkout when the
/// "open agent on checkout" setting is enabled.
@discardableResult
func launchAgentSession(
    dir: String,
    agent: CodingAgent,
    destination: AgentDestination,
    runner: ProcessRunning,
    writeScript: (String) -> String? = writeCommandScript,
    waitForApp: (CodingAgent) -> Void = waitForDesktopApp
) -> Bool {
    switch destination {
    case .terminal(let appPath):
        return launchScript(
            agentSessionScriptContents(dir: dir, agent: agent),
            appPath: appPath, runner: runner, writeScript: writeScript
        )
    case .desktopApp:
        return openInDesktopApp(agent, dir: dir, prompt: nil, runner: runner, waitForApp: waitForApp)
    }
}
