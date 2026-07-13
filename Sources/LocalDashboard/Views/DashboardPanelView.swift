import SwiftUI
import AppKit

struct DashboardPanelView: View {
    @ObservedObject var store: DashboardStore
    @State private var refreshBounce = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PullRequestsSectionView(
                pullRequests: store.pullRequests,
                unavailable: store.prsUnavailable,
                closedPullRequests: store.closedPullRequests,
                closedUnavailable: store.closedUnavailable,
                closedLoaded: store.closedLoaded,
                filter: Binding(
                    get: { store.filter },
                    set: { store.selectFilter($0) }
                ),
                maxContentHeight: maxContentHeight,
                onCheckout: { store.checkoutPullRequest($0) }
            )
            Divider()
            HStack {
                Button {
                    refreshBounce += 1
                    store.refreshCurrentFilter()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .bounceOnValueChange(refreshBounce)
                }
                .buttonStyle(.plain)
                .help("Refresh")

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
                .help("Quit LocalDashboard")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(width: 380)
    }

    /// Cap the scrollable list so the whole popover stays within 40% of the screen height,
    /// reserving room for the header, divider, and footer chrome.
    private var maxContentHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        return max(200, screenHeight * 0.4 - 96)
    }
}

private extension View {
    @ViewBuilder
    func bounceOnValueChange(_ value: Int) -> some View {
        if #available(macOS 14.0, *) {
            self.symbolEffect(.bounce, value: value)
        } else {
            self
        }
    }
}
