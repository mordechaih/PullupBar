import Foundation

private let defaultGitPath = "/usr/bin/git"

/// The instruction handed to the Claude Code session opened by the Create-PR action.
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

/// The `.command` script body: enter the clone, check out the branch, then launch Claude Code.
func prDraftScriptContents(dir: String, branch: String, prompt: String) -> String {
    """
    #!/bin/sh
    cd \(shellQuote(dir)) && git checkout \(shellQuote(branch)) && claude \(shellQuote(prompt))
    """
}

/// Default: write the PR-draft script to a temp `.command` file and mark it executable.
/// Returns the file path, or nil if writing fails.
private func writePRDraftScript(_ contents: String) -> String? {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("pullupbar-createpr-\(UUID().uuidString).command")
    do {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    } catch {
        return nil
    }
}

/// Writes the PR-draft script, then runs the user's launch `command` (with `{script}` replaced by
/// the script path) through `/bin/sh -c`, so templates like `open {script}` or
/// `open -a iTerm {script}` work. `writeScript` is injected for tests.
@discardableResult
func launchPRDraftSession(
    _ branch: BranchInfo,
    command: String,
    runner: ProcessRunning,
    writeScript: (String) -> String? = writePRDraftScript
) -> Bool {
    let contents = prDraftScriptContents(dir: branch.localCloneDir, branch: branch.name, prompt: prDraftPrompt)
    guard let scriptPath = writeScript(contents) else { return false }
    let resolved = command.replacingOccurrences(of: "{script}", with: scriptPath)
    return runner.run("/bin/sh", ["-c", resolved]) != nil
}
