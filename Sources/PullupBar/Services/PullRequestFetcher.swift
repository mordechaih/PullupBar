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

/// Caches the resolved `gh` path for the process lifetime. Resolving it spawns a login shell
/// (`$SHELL -l -c …`, which sources the user's full dotfile chain) and the location never
/// changes within a session, so doing it once instead of on every poll/tab fetch is a large
/// win. Only successful resolutions are cached; a failed lookup is retried next time (the user
/// may install `gh` after launch). The first caller resolves while others wait on the lock,
/// so a cold launch spawns one login shell rather than three at once.
final class GHPathCache: @unchecked Sendable {
    static let shared = GHPathCache()

    private let lock = NSLock()
    private var cached: String?

    func path(
        runner: ProcessRunning,
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let resolved = resolveGHExecutablePath(runner: runner, fileExists: fileExists)
        cached = resolved
        return resolved
    }
}

func fetchPullRequests(
    runner: ProcessRunning,
    state: PullRequestFilter = .open,
    closedLimit: Int = 20,
    pathCache: GHPathCache = .shared
) -> [PullRequestInfo]? {
    switch state {
    case .open: return fetchOpenPullRequests(runner: runner, pathCache: pathCache)
    // Merged and closed-unmerged PRs come from the same closed fetch; the view splits them by tab.
    case .merged, .closed: return fetchClosedPullRequests(runner: runner, limit: closedLimit, pathCache: pathCache)
    // The No PR tab uses fetchBranchesWithoutPR, not this PR fetch; never reached in practice.
    case .noPR: return nil
    }
}

/// Open PRs are searched and then enriched with CI/review/mergeable/diff detail. The per-PR
/// `gh pr view` calls are independent, so they run concurrently — load time is one detail call,
/// not one per PR. Results keep the search order.
private func fetchOpenPullRequests(runner: ProcessRunning, pathCache: GHPathCache) -> [PullRequestInfo]? {
    guard let ghPath = pathCache.path(runner: runner) else { return nil }

    guard let searchOutput = runner.run(ghPath, [
        "search", "prs", "--author=@me", "--state=open",
        "--json", "number,title,url,isDraft,repository,createdAt"
    ]), let searchData = searchOutput.data(using: .utf8) else { return nil }

    let prs = parseSearchResults(searchData)

    return runConcurrently(prs.map { pr in
        {
            guard let detailOutput = runner.run(ghPath, [
                "pr", "view", "\(pr.number)", "--repo", pr.repo,
                "--json", "statusCheckRollup,reviewDecision,mergeable,additions,deletions,changedFiles"
            ]), let detailData = detailOutput.data(using: .utf8) else {
                return pr
            }
            return enrichPullRequest(pr, withDetailJSON: detailData)
        }
    })
}

/// Closed PRs are fetched with two cheap searches (merged vs. closed-unmerged) and are
/// deliberately not enriched — closed PRs need no CI/review status and per-PR `gh pr view`
/// calls would make loading slow. Results are merged and sorted newest-closed first.
/// `limit` caps each of the two searches (configurable via Settings).
private func fetchClosedPullRequests(runner: ProcessRunning, limit: Int, pathCache: GHPathCache) -> [PullRequestInfo]? {
    guard let ghPath = pathCache.path(runner: runner) else { return nil }

    let fields = "number,title,url,isDraft,repository,createdAt,closedAt"
    let limitArg = String(max(1, limit))

    // The two searches are independent, so run them concurrently rather than back-to-back.
    let outputs = runConcurrently([
        { runner.run(ghPath, [
            "search", "prs", "--author=@me", "--merged", "--sort", "updated", "--limit", limitArg, "--json", fields
        ]) },
        { runner.run(ghPath, [
            "search", "prs", "--author=@me", "--state=closed", "is:unmerged", "--sort", "updated", "--limit", limitArg, "--json", fields
        ]) },
    ])
    let mergedOutput = outputs[0]
    let unmergedOutput = outputs[1]

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
