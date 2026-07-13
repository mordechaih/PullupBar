import Foundation

func resolveGHExecutablePath(runner: ProcessRunning) -> String? {
    guard let output = runner.run("/bin/zsh", ["-l", "-c", "command -v gh"]) else { return nil }
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func fetchPullRequests(runner: ProcessRunning) -> [PullRequestInfo]? {
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
            "--json", "statusCheckRollup,reviewDecision,mergeable"
        ]), let detailData = detailOutput.data(using: .utf8) else {
            enriched.append(pr)
            continue
        }
        enriched.append(enrichPullRequest(pr, withDetailJSON: detailData))
    }
    return enriched
}
