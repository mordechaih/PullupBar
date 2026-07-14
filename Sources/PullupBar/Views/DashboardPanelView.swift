import SwiftUI
import AppKit

struct DashboardPanelView: View {
    @ObservedObject var store: DashboardStore
    @State private var refreshRotate = 0
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showingSettings {
                SettingsView(settings: store.settings, maxContentHeight: maxContentHeight)
            } else {
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
                    onCheckout: { store.checkoutPullRequest($0) },
                    branches: store.noPRBranches,
                    branchesLoaded: store.branchesLoaded,
                    branchesUnavailable: store.branchesUnavailable,
                    onCheckoutBranch: { store.checkoutBranch($0) },
                    onCreatePR: { store.createPRForBranch($0) },
                    onArchiveBranch: { store.archiveBranch($0) }
                )
            }
            Divider()
            footer
        }
        .frame(width: 380)
    }

    private var footer: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showingSettings.toggle() }
            } label: {
                Image(systemName: showingSettings ? "chevron.left" : "gearshape")
            }
            .buttonStyle(.plain)
            .help(showingSettings ? "Back" : "Settings")

            if !showingSettings {
                Button {
                    refreshRotate += 1
                    store.refreshCurrentFilter()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotateOnValueChange(refreshRotate)
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Quit PullupBar")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
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
    func rotateOnValueChange(_ value: Int) -> some View {
        if #available(macOS 15.0, *) {
            self.symbolEffect(.rotate, value: value)
        } else if #available(macOS 14.0, *) {
            self.symbolEffect(.bounce, value: value)
        } else {
            self
        }
    }
}
