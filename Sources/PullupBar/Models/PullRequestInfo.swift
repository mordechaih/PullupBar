import Foundation

struct PullRequestInfo: Identifiable, Sendable {
    let id: String
    let number: Int
    let title: String
    let url: String
    let repo: String
    let isDraft: Bool
    let createdAt: Date
    var ciStatus: String = "PENDING"
    var reviewDecision: String?
    var isConflicting: Bool = false
    var additions: Int = 0
    var deletions: Int = 0
    var changedFiles: Int = 0
    var isMerged: Bool = false
    var closedAt: Date? = nil

    var ageDays: Int {
        max(0, Int(Date().timeIntervalSince(createdAt) / 86400))
    }

    /// Days since the PR was closed/merged, for the closed view's recency label.
    /// Nil for open PRs, which have no `closedAt`.
    var closedAgeDays: Int? {
        closedAt.map { max(0, Int(Date().timeIntervalSince($0) / 86400)) }
    }
}

/// Selects which tab of the dashboard's segmented switcher is showing. Open/merged/closed draw
/// from pull-request fetches; `noPR` shows local/remote branches that never had a PR.
enum PullRequestFilter: String, CaseIterable, Sendable {
    case open
    case merged
    case closed
    case noPR

    var label: String {
        switch self {
        case .open: return "Open"
        case .merged: return "Merged"
        case .closed: return "Closed"
        case .noPR: return "No PR"
        }
    }

    /// Whether this tab draws from the closed-PR fetch (merged + closed-unmerged) rather than open
    /// PRs. The `noPR` tab draws from its own branch fetch, so it is not a closed tab.
    var isClosedTab: Bool { self == .merged || self == .closed }
}

enum PullRequestTriageLane: String, CaseIterable, Sendable {
    case needsAttention
    case awaitingReview
    case readyToMerge
    case draft

    var label: String {
        switch self {
        case .needsAttention: return "Needs attention"
        case .awaitingReview: return "Awaiting review"
        case .readyToMerge: return "Ready to merge"
        case .draft: return "Draft"
        }
    }
}

func triageLane(for pr: PullRequestInfo) -> PullRequestTriageLane {
    if pr.isDraft { return .draft }
    if pr.ciStatus == "FAILURE" || pr.reviewDecision == "CHANGES_REQUESTED" || pr.isConflicting {
        return .needsAttention
    }
    if pr.ciStatus == "SUCCESS" && pr.reviewDecision == "APPROVED" {
        return .readyToMerge
    }
    return .awaitingReview
}

private struct SearchRepository: Decodable {
    let nameWithOwner: String
}

private struct SearchResultItem: Decodable {
    let number: Int
    let title: String
    let url: String
    let isDraft: Bool
    let repository: SearchRepository
    let createdAt: String
    let closedAt: String?
}

private let ghDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

func parseSearchResults(_ data: Data, isMerged: Bool = false) -> [PullRequestInfo] {
    guard let items = try? JSONDecoder().decode([SearchResultItem].self, from: data) else { return [] }

    return items.compactMap { item in
        guard let created = ghDateFormatter.date(from: item.createdAt) else { return nil }
        return PullRequestInfo(
            id: "\(item.repository.nameWithOwner)#\(item.number)",
            number: item.number,
            title: item.title,
            url: item.url,
            repo: item.repository.nameWithOwner,
            isDraft: item.isDraft,
            createdAt: created,
            isMerged: isMerged,
            closedAt: item.closedAt.flatMap { ghDateFormatter.date(from: $0) }
        )
    }
}

private struct CheckRun: Decodable {
    let conclusion: String?
    let state: String?
}

private struct DetailResult: Decodable {
    let statusCheckRollup: [CheckRun]?
    let reviewDecision: String?
    let mergeable: String?
    let additions: Int?
    let deletions: Int?
    let changedFiles: Int?
}

func enrichPullRequest(_ pr: PullRequestInfo, withDetailJSON data: Data) -> PullRequestInfo {
    guard let detail = try? JSONDecoder().decode(DetailResult.self, from: data) else { return pr }

    var updated = pr
    let states = (detail.statusCheckRollup ?? []).map { $0.conclusion ?? $0.state ?? "PENDING" }

    let failureStates: Set<String> = ["FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE"]
    let successStates: Set<String> = ["SUCCESS", "NEUTRAL", "SKIPPED", "EXPECTED"]

    if states.isEmpty {
        updated.ciStatus = "PENDING"
    } else if states.contains(where: { failureStates.contains($0) }) {
        updated.ciStatus = "FAILURE"
    } else if states.allSatisfy({ successStates.contains($0) }) {
        updated.ciStatus = "SUCCESS"
    } else {
        updated.ciStatus = "PENDING"
    }

    updated.reviewDecision = (detail.reviewDecision?.isEmpty == false) ? detail.reviewDecision : nil
    updated.isConflicting = detail.mergeable == "CONFLICTING"
    updated.additions = detail.additions ?? 0
    updated.deletions = detail.deletions ?? 0
    updated.changedFiles = detail.changedFiles ?? 0
    return updated
}
