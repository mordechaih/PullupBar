import Foundation

/// Common locations where Homebrew (Apple Silicon / Intel), the system, and MacPorts install `gh`.
/// Used as a fallback when a login-shell lookup can't find it on the user's PATH.
private let commonGHExecutablePaths = [
    "/opt/homebrew/bin/gh",
    "/usr/local/bin/gh",
    "/usr/bin/gh",
    "/opt/local/bin/gh",
]

/// Resolves the `gh` executable. Prefers what the user's login shell finds (honoring their
/// PATH, Homebrew shellenv, etc.), then falls back to well-known install locations so `gh`
/// is still found when it isn't on the login-shell PATH. `shellPath` defaults to the user's
/// `$SHELL` rather than a hardcoded `/bin/zsh`, so bash/fish users work too.
func resolveGHExecutablePath(
    runner: ProcessRunning,
    shellPath: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
    fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
) -> String? {
    if let output = runner.run(shellPath, ["-l", "-c", "command -v gh"]) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
    }
    for candidate in commonGHExecutablePaths where fileExists(candidate) {
        return candidate
    }
    return nil
}

func fetchPullRequests(runner: ProcessRunning, state: PullRequestFilter = .open, closedLimit: Int = 20) -> [PullRequestInfo]? {
    switch state {
    case .open: return fetchOpenPullRequests(runner: runner)
    // Merged and closed-unmerged PRs come from the same closed fetch; the view splits them by tab.
    case .merged, .closed: return fetchClosedPullRequests(runner: runner, limit: closedLimit)
    }
}

/// Open PRs are searched and then enriched one-by-one with CI/review/mergeable/diff detail.
private func fetchOpenPullRequests(runner: ProcessRunning) -> [PullRequestInfo]? {
    guard let ghPath = resolveGHExecutablePath(runner: runner) else { return nil }

    guard let searchOutput = runner.run(ghPath, [
        "search", "prs", "--author=@me", "--state=open",
        "--json", "number,title,url,isDraft,repository,createdAt"
    ]), let searchData = searchOutput.data(using: .utf8) else { return nil }

    let prs = parseSearchResults(searchData)

    var enriched: [PullRequestInfo] = []
    for pr in prs {
        guard let detailOutput = runner.run(ghPath, [
            "pr", "view", "\(pr.number)", "--repo", pr.repo,
            "--json", "statusCheckRollup,reviewDecision,mergeable,additions,deletions,changedFiles"
        ]), let detailData = detailOutput.data(using: .utf8) else {
            enriched.append(pr)
            continue
        }
        enriched.append(enrichPullRequest(pr, withDetailJSON: detailData))
    }
    return enriched
}

/// Closed PRs are fetched with two cheap searches (merged vs. closed-unmerged) and are
/// deliberately not enriched — closed PRs need no CI/review status and per-PR `gh pr view`
/// calls would make loading slow. Results are merged and sorted newest-closed first.
/// `limit` caps each of the two searches (configurable via Settings).
private func fetchClosedPullRequests(runner: ProcessRunning, limit: Int) -> [PullRequestInfo]? {
    guard let ghPath = resolveGHExecutablePath(runner: runner) else { return nil }

    let fields = "number,title,url,isDraft,repository,createdAt,closedAt"
    let limitArg = String(max(1, limit))

    let mergedOutput = runner.run(ghPath, [
        "search", "prs", "--author=@me", "--merged", "--sort", "updated", "--limit", limitArg, "--json", fields
    ])
    let unmergedOutput = runner.run(ghPath, [
        "search", "prs", "--author=@me", "--state=closed", "is:unmerged", "--sort", "updated", "--limit", limitArg, "--json", fields
    ])

    // If both searches failed, the feature is unavailable; a single empty result is fine.
    guard mergedOutput != nil || unmergedOutput != nil else { return nil }

    var results: [PullRequestInfo] = []
    if let data = mergedOutput?.data(using: .utf8) {
        results += parseSearchResults(data, isMerged: true)
    }
    if let data = unmergedOutput?.data(using: .utf8) {
        results += parseSearchResults(data, isMerged: false)
    }

    return results.sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }
}
