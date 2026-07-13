import SwiftUI

struct PullRequestsSectionView: View {
    let pullRequests: [PullRequestInfo]
    let unavailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pull Requests").font(.headline)

            if unavailable {
                Text("Unavailable").foregroundStyle(.secondary)
            } else if pullRequests.isEmpty {
                Text("No open PRs").foregroundStyle(.secondary)
            } else {
                ForEach(pullRequests) { pr in
                    HStack(spacing: 6) {
                        Text("#\(pr.number) \(pr.title)")
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if pr.isDraft {
                            tag("draft", .secondary)
                        }
                        if pr.reviewDecision == "APPROVED" {
                            tag("approved", .green)
                        } else if pr.reviewDecision == "CHANGES_REQUESTED" {
                            tag("changes", .red)
                        }
                        if pr.isConflicting {
                            tag("conflicts", .red)
                        }
                        ciDot(pr.ciStatus)
                        Spacer(minLength: 8)
                        Text(ageLabel(pr.ageDays))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func ciDot(_ status: String) -> some View {
        let color: Color = status == "SUCCESS" ? .green : (status == "FAILURE" ? .red : .yellow)
        return Circle().fill(color).frame(width: 8, height: 8)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func ageLabel(_ days: Int) -> String {
        if days >= 7 { return "\(days / 7)w" }
        if days >= 1 { return "\(days)d" }
        return "<1d"
    }
}
