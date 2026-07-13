import SwiftUI
import AppKit

struct PullRequestsSectionView: View {
    let pullRequests: [PullRequestInfo]
    let unavailable: Bool
    let closedPullRequests: [PullRequestInfo]
    let closedUnavailable: Bool
    let closedLoaded: Bool
    @Binding var filter: PullRequestFilter
    let maxContentHeight: CGFloat
    let onCheckout: (PullRequestInfo) -> Void
    let branches: [BranchInfo]
    let branchesLoaded: Bool
    let branchesUnavailable: Bool
    let onRefreshBranches: () -> Void
    let onCheckoutBranch: (BranchInfo) -> Void
    let onCreatePR: (BranchInfo) -> Void
    let onArchiveBranch: (BranchInfo) -> Void

    /// One page spans the full window width; the 16pt horizontal breathing room lives *inside*
    /// each page (see `page`) so the clip sits at the window edge and the spring overshoot slides
    /// into the padding instead of slicing chips at the padding line.
    private static let pageWidth: CGFloat = 380
    private static let pagePadding: CGFloat = 16
    private static let slide: Animation = .spring(response: 0.4, dampingFraction: 0.85)

    /// The header sits on top of the scroll content: `headerHeight` is the solid band the title
    /// and picker occupy; `headerFade` is the extra region below it where the frosted backdrop
    /// tapers to clear. Scroll content is inset by their sum so, at rest, the first row sits just
    /// below the fade and only blurs as it scrolls up under the header.
    private static let headerHeight: CGFloat = 44
    private static let headerFade: CGFloat = 24
    private var contentTopInset: CGFloat { Self.headerHeight + Self.headerFade }

    /// The popover is fixed to this height so its hosting window never resizes (MenuBarExtra
    /// can't animate that), keeping the toggle a pure, snap-free horizontal slide. Each page
    /// scrolls within it; shorter views leave empty space below.
    private var fixedHeight: CGFloat { min(420, maxContentHeight) }

    var body: some View {
        ZStack(alignment: .top) {
            pager
            headerBlur
            headerContent
        }
        .frame(width: Self.pageWidth, height: fixedHeight)
    }

    /// The two views sit side by side in a row twice as wide as the window; a single horizontal
    /// offset slides the outgoing view off one edge while the incoming view arrives from the
    /// other, so there's one continuous motion with a clear spatial relationship. Height is
    /// fixed, so the toggle never resizes the window.
    private var pager: some View {
        HStack(alignment: .top, spacing: 0) {
            page(openContent)
            page(mergedContent)
            page(closedContent)
        }
        .offset(x: -CGFloat(selectedIndex) * Self.pageWidth)
        .frame(width: Self.pageWidth, height: fixedHeight, alignment: .topLeading)
        .clipped()
        .animation(Self.slide, value: filter)
    }

    /// Frosted backdrop pinned to the top: solid over the header band, then tapering to clear
    /// so rows scrolling up dissolve into a progressive blur beneath the header rather than
    /// hitting a hard clip line.
    private var headerBlur: some View {
        let total = Self.headerHeight + Self.headerFade
        return Rectangle()
            .fill(.ultraThinMaterial)
            .frame(width: Self.pageWidth, height: total)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: Self.headerHeight / total),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
    }

    private var headerContent: some View {
        HStack {
            Text("Pull Requests").font(.headline)
            Spacer()
            Picker("", selection: $filter) {
                ForEach(PullRequestFilter.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, Self.pagePadding)
        .frame(width: Self.pageWidth, height: Self.headerHeight)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var selectedIndex: Int {
        switch filter {
        case .open: return 0
        case .merged: return 1
        case .closed: return 2
        }
    }

    /// One page, fixed to the window's width and height and scrollable within it. Content is
    /// inset at the top so it starts below the header and slides up under it as you scroll.
    private func page(_ content: some View) -> some View {
        ScrollView {
            content
                .padding(.horizontal, Self.pagePadding)
                .padding(.top, contentTopInset)
                .frame(width: Self.pageWidth, alignment: .topLeading)
        }
        .frame(width: Self.pageWidth, height: fixedHeight)
    }

    @ViewBuilder
    private var openContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if unavailable {
                Text("Unavailable").foregroundStyle(.secondary)
            } else if pullRequests.isEmpty {
                Text("No open PRs").foregroundStyle(.secondary)
            } else {
                ForEach(PullRequestTriageLane.allCases, id: \.self) { lane in
                    let items = pullRequests.filter { triageLane(for: $0) == lane }
                    if !items.isEmpty {
                        LaneSectionView(lane: lane, pullRequests: items, onCheckout: onCheckout)
                    }
                }
            }
            BranchesSectionView(
                branches: branches,
                loaded: branchesLoaded,
                unavailable: branchesUnavailable,
                onRefresh: onRefreshBranches,
                onCheckout: onCheckoutBranch,
                onCreatePR: onCreatePR,
                onArchive: onArchiveBranch
            )
        }
    }

    @ViewBuilder
    private var mergedContent: some View {
        closedTab(
            items: closedPullRequests.filter { $0.isMerged },
            label: "Merged", icon: "arrow.triangle.merge", color: .purple,
            emptyLabel: "No merged PRs"
        )
    }

    @ViewBuilder
    private var closedContent: some View {
        closedTab(
            items: closedPullRequests.filter { !$0.isMerged },
            label: "Closed", icon: "xmark.circle", color: .red,
            emptyLabel: "No closed PRs"
        )
    }

    /// Merged and Closed are their own tabs, each headed by a colored icon + label (the count
    /// shows once loaded) over a flat, newest-first list of chips. Both share the closed fetch's
    /// loading/unavailable states. The Open tab keeps its own per-lane headers instead.
    @ViewBuilder
    private func closedTab(items: [PullRequestInfo], label: String, icon: String, color: Color, emptyLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(color)
                Text(label).font(.system(size: 13)).fontWeight(.bold)
                Spacer()
                if closedLoaded && !closedUnavailable {
                    Text("\(items.count)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            closedTabBody(items: items, emptyLabel: emptyLabel)
        }
    }

    @ViewBuilder
    private func closedTabBody(items: [PullRequestInfo], emptyLabel: String) -> some View {
        if !closedLoaded {
            Text("Loading…").foregroundStyle(.secondary)
        } else if closedUnavailable {
            Text("Unavailable").foregroundStyle(.secondary)
        } else if items.isEmpty {
            Text(emptyLabel).foregroundStyle(.secondary)
        } else {
            ForEach(items) { pr in
                PullRequestChip(pr: pr, onCheckout: onCheckout)
            }
        }
    }
}

private struct LaneSectionView: View {
    let lane: PullRequestTriageLane
    let pullRequests: [PullRequestInfo]
    let onCheckout: (PullRequestInfo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: laneIcon)
                    .font(.system(size: 13))
                    .foregroundStyle(laneColor)
                Text(lane.label).font(.system(size: 13)).fontWeight(.bold)
                Spacer()
                Text("\(pullRequests.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ForEach(pullRequests) { pr in
                PullRequestChip(pr: pr, onCheckout: onCheckout)
            }
        }
    }

    private var laneColor: Color {
        switch lane {
        case .needsAttention: return .red
        case .awaitingReview: return .yellow
        case .readyToMerge: return .green
        case .draft: return .secondary
        }
    }

    private var laneIcon: String {
        switch lane {
        case .needsAttention: return "exclamationmark.triangle.fill"
        case .awaitingReview: return "hourglass"
        case .readyToMerge: return "checkmark"
        case .draft: return "pencil"
        }
    }
}

private struct PullRequestChip: View {
    let pr: PullRequestInfo
    let onCheckout: (PullRequestInfo) -> Void
    @State private var isHovered = false

    private static let hoverSpring: Animation = .spring(response: 0.3, dampingFraction: 0.7)
    /// Width of the frosted scrim: covers the 3-icon pill (~112pt) plus a fade region to its left.
    private static let scrimWidth: CGFloat = 200

    var body: some View {
        textContent
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            // Scrim + pill overlay the full card (outside the padding) so the frosted region
            // reaches the card edges; the clip keeps it inside the rounded corners.
            .overlay(alignment: .trailing) { blurScrim }
            .overlay(alignment: .trailing) { hoverActions.padding(.trailing, 10) }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            // A hairline highlight along the top edge that fades to transparent toward the bottom.
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.25), .white.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
            .animation(Self.hoverSpring, value: isHovered)
            .onHover { hovering in isHovered = hovering }
            .onTapGesture {
                guard let url = URL(string: pr.url) else { return }
                NSWorkspace.shared.open(url)
            }
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleText
            metaRow
        }
    }

    /// A frosted-glass scrim anchored to the trailing edge that sits beneath the hover pill and
    /// fades out to the left. Material samples and blurs the row text rendered behind it, so the
    /// text dissolves into a blur behind the icons instead of colliding with them. The gradient
    /// mask (clear on the left, opaque on the right) is what makes the blur "extend left" of the
    /// pill and taper away.
    private var blurScrim: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .frame(width: Self.scrimWidth)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.45)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
            .allowsHitTesting(false)
            .opacity(isHovered ? 1 : 0)
    }

    private var titleText: some View {
        Text(pr.title)
            .foregroundColor(.primary)
            .font(.system(size: 13))
            .fontWeight(.semibold)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            // The repo#number identifier must never truncate — fixedSize keeps it at its
            // natural width so the diff/file counts give way first if space runs short.
            // verbatim: a plain Text literal is a LocalizedStringKey, which locale-formats the
            // integer and inserts thousands separators (e.g. "1,234"). PR numbers take no commas.
            Text(verbatim: "\(repoShortName)#\(pr.number)")
                .fixedSize()
                .layoutPriority(1)
            // Closed PRs aren't enriched with diff stats, so show when they were
            // merged/closed instead. Open PRs get diff/file counts + age on the right.
            if let closedAge = pr.closedAgeDays {
                Spacer()
                Text("\(pr.isMerged ? "merged" : "closed") \(ageLabel(closedAge)) ago")
            } else {
                Text("·")
                diffStatText
                HStack(spacing: 3) {
                    Image(systemName: changedFilesSymbol)
                    Text("\(pr.changedFiles)")
                }
                Spacer()
                Text(ageLabel(pr.ageDays))
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var hoverActions: some View {
        // Items are indexed right-to-left so the stagger emanates from the trailing anchor:
        // the rightmost icon (index 0) pops in first, then cascades left.
        HStack(spacing: 4) {
            OpenPRIconButton(url: pr.url).staggeredScale(isActive: isHovered, index: 2)
            // Checkout is hidden for closed PRs — their branch is often already deleted.
            if pr.closedAt == nil {
                CheckoutIconButton(pr: pr, onCheckout: onCheckout).staggeredScale(isActive: isHovered, index: 1)
            }
            CopyLinkIconButton(url: pr.url).staggeredScale(isActive: isHovered, index: 0)
        }
        .padding(.horizontal, 6)
        .scaleEffect(isHovered ? 1 : 0.7, anchor: .trailing)
        .opacity(isHovered ? 1 : 0)
    }

    private var diffStatText: some View {
        HStack(spacing: 4) {
            Text("+\(pr.additions)").foregroundStyle(Color.green.opacity(0.75))
            Text("−\(pr.deletions)").foregroundStyle(Color.red.opacity(0.75))
        }
    }

    private var repoShortName: String {
        pr.repo.split(separator: "/").last.map(String.init) ?? pr.repo
    }

    /// Plus badge when the PR is net-additive (or neutral), minus badge when more lines are
    /// deleted than added.
    private var changedFilesSymbol: String {
        pr.additions - pr.deletions < 0 ? "rectangle.stack.fill.badge.minus" : "rectangle.stack.fill.badge.plus"
    }
}

private func ageLabel(_ days: Int) -> String {
    if days >= 7 { return "\(days / 7)w" }
    if days >= 1 { return "\(days)d" }
    return "<1d"
}

private struct OpenPRIconButton: View {
    let url: String
    @State private var tapTrigger = 0

    var body: some View {
        Button {
            tapTrigger += 1
            guard let target = URL(string: url) else { return }
            NSWorkspace.shared.open(target)
        } label: {
            OcticonImage(paths: Octicons.tabExternal)
                .tapBounce(tapTrigger)
        }
        .buttonStyle(.plain)
        .iconHoverEffect()
        .help("Open on GitHub")
    }
}

private struct CheckoutIconButton: View {
    let pr: PullRequestInfo
    let onCheckout: (PullRequestInfo) -> Void
    @State private var tapTrigger = 0

    var body: some View {
        Button {
            tapTrigger += 1
            onCheckout(pr)
        } label: {
            OcticonImage(paths: Octicons.gitBranchCheck)
                .tapBounce(tapTrigger)
        }
        .buttonStyle(.plain)
        .iconHoverEffect()
        .help("Check out this branch locally")
    }
}

private struct CopyLinkIconButton: View {
    let url: String
    @State private var copied = false
    @State private var tapTrigger = 0

    var body: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(url, forType: .string)
            copied = true
            tapTrigger += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                copied = false
            }
        } label: {
            // Fixed footprint so the octicon↔checkmark crossfade doesn't shift the row.
            icon
                .frame(width: 16, height: 16)
                .tapBounce(tapTrigger)
                .animation(.easeInOut(duration: 0.2), value: copied)
        }
        .buttonStyle(.plain)
        .foregroundStyle(copied ? Color.green : Color.primary)
        .iconHoverEffect()
        .help("Copy PR link")
    }

    // The link Octicon swaps to a checkmark on copy; a brief crossfade covers the swap since a
    // shape can't use SF Symbols' contentTransition.
    @ViewBuilder
    private var icon: some View {
        if copied {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .semibold))
                .transition(.opacity)
        } else {
            OcticonImage(paths: Octicons.link)
                .transition(.opacity)
        }
    }
}

/// A quick pop-and-settle scale pulse fired whenever `trigger` changes — tap feedback for the
/// custom Octicon shapes, which can't use SF Symbols' `.symbolEffect(.bounce)`.
private struct TapBounceModifier: ViewModifier {
    let trigger: Int
    @State private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: trigger) { _ in
                withAnimation(.spring(response: 0.15, dampingFraction: 0.35)) { scale = 1.35 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) { scale = 1 }
                }
            }
    }
}

private extension View {
    func tapBounce(_ trigger: Int) -> some View {
        modifier(TapBounceModifier(trigger: trigger))
    }
}

private struct IconHoverModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: 16))
            .padding(6)
            .background(Circle().fill(isHovering ? Color.secondary.opacity(0.18) : Color.clear))
            .scaleEffect(isHovering ? 1.15 : 1)
            .onHover { hovering in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                    isHovering = hovering
                }
            }
    }
}

private extension View {
    func iconHoverEffect() -> some View {
        modifier(IconHoverModifier())
    }
}

/// Scales an item in from its center with a per-index delay so a row of items pops in on a
/// stagger. The delay only applies on the way in; on the way out everything collapses together.
private struct StaggeredScaleModifier: ViewModifier {
    let isActive: Bool
    let index: Int
    private static let perItemDelay: Double = 0.05

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive ? 1 : 0.3)
            .opacity(isActive ? 1 : 0)
            .animation(
                .spring(response: 0.3, dampingFraction: 0.6)
                    .delay(isActive ? Double(index) * Self.perItemDelay : 0),
                value: isActive
            )
    }
}

private extension View {
    func staggeredScale(isActive: Bool, index: Int) -> some View {
        modifier(StaggeredScaleModifier(isActive: isActive, index: index))
    }
}
