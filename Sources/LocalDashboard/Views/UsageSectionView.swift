import SwiftUI

struct UsageSectionView: View {
    let usage: UsageWindowInfo?
    let unavailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Usage").font(.headline)

            if unavailable {
                Text("Unavailable").foregroundStyle(.secondary)
            } else if let usage {
                Text("\(usage.usedPercent)%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(color(for: usage.usedPercent))
                ProgressView(value: Double(usage.usedPercent), total: 100)
                    .tint(color(for: usage.usedPercent))
                Text(String(format: "$%.2f / $%.0f", usage.usedUSD, usage.limitUSD))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Loading…").foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func color(for percent: Int) -> Color {
        if percent > 80 { return .red }
        if percent > 50 { return .yellow }
        return .green
    }
}
