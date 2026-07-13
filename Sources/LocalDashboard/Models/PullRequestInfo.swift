import Foundation

struct PullRequestInfo: Identifiable, Sendable {
    let id: Int
    let number: Int
    let title: String
    let url: String
    let repo: String
    let isDraft: Bool
    let createdAt: Date
    var ciStatus: String = "PENDING"
    var reviewDecision: String?
    var isConflicting: Bool = false

    var ageDays: Int {
        max(0, Int(Date().timeIntervalSince(createdAt) / 86400))
    }
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
}

private let ghDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

func parseSearchResults(_ data: Data) -> [PullRequestInfo] {
    guard let items = try? JSONDecoder().decode([SearchResultItem].self, from: data) else { return [] }

    return items.compactMap { item in
        guard let created = ghDateFormatter.date(from: item.createdAt) else { return nil }
        return PullRequestInfo(
            id: item.number,
            number: item.number,
            title: item.title,
            url: item.url,
            repo: item.repository.nameWithOwner,
            isDraft: item.isDraft,
            createdAt: created
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
    return updated
}
