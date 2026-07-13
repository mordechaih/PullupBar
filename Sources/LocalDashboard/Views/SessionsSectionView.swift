import SwiftUI

struct SessionsSectionView: View {
    let rows: [SessionRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sessions").font(.headline)

            if rows.isEmpty {
                Text("No active sessions").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                    ForEach(rows) { row in
                        GridRow {
                            Circle()
                                .fill(row.status == "busy" ? Color.yellow : Color.green)
                                .frame(width: 8, height: 8)
                            Text(row.name).lineLimit(1)
                            ProgressView(value: Double(row.contextPercent), total: 100)
                                .frame(width: 60)
                            Text("\(row.contextPercent)%")
                                .font(.caption)
                                .monospacedDigit()
                            Text(String(format: "$%.2f", row.costUSD))
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
