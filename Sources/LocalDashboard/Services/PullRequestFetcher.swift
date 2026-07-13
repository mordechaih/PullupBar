import Foundation

func resolveGHExecutablePath(runner: ProcessRunning) -> String? {
    guard let output = runner.run("/bin/zsh", ["-l", "-c", "command -v gh"]) else { return nil }
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func fetchPullRequests(runner: ProcessRunning, state: PullRequestFilter = .open) -> [PullRequestInfo]? {
    switch state {
    case .open: return fetchOpenPullRequests(runner: runner)
    case .closed: return fetchClosedPullRequests(runner: runner)
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
private func fetchClosedPullRequests(runner: ProcessRunning) -> [PullRequestInfo]? {
    guard let ghPath = resolveGHExecutablePath(runner: runner) else { return nil }

    let fields = "number,title,url,isDraft,repository,createdAt,closedAt"

    let mergedOutput = runner.run(ghPath, [
        "search", "prs", "--author=@me", "--merged", "--sort", "updated", "--limit", "20", "--json", fields
    ])
    let unmergedOutput = runner.run(ghPath, [
        "search", "prs", "--author=@me", "--state=closed", "is:unmerged", "--sort", "updated", "--limit", "20", "--json", fields
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
