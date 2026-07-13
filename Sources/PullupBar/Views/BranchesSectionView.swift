import SwiftUI

/// The "No PR" tab's content: local/remote branches that never had a PR. Owns its in-page header
/// (icon + title + count, mirroring the Merged/Closed tabs) and its loading / unavailable / empty
/// / list states. Refresh is handled by the shared footer button, not a per-tab control.
struct BranchesSectionView: View {
    let branches: [BranchInfo]
    let loaded: Bool
    let unavailable: Bool
    let onCheckout: (BranchInfo) -> Void
    let onCreatePR: (BranchInfo) -> Void
    let onArchive: (BranchInfo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            body(for: branches)
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.branch")
                .font(.system(size: 13))
                .foregroundStyle(.teal)
            Text("Branches without a PR").font(.system(size: 13)).fontWeight(.bold)
            Spacer()
            if loaded && !unavailable {
                Text("\(branches.count)").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func body(for branches: [BranchInfo]) -> some View {
        if !loaded {
            Text("Loading…").foregroundStyle(.secondary).font(.system(size: 12))
        } else if unavailable {
            Text("Unavailable").foregroundStyle(.secondary).font(.system(size: 12))
        } else if branches.isEmpty {
            Text("No branches without a PR").foregroundStyle(.secondary).font(.system(size: 12))
        } else {
            ForEach(branches) { branch in
                BranchChip(branch: branch, onCheckout: onCheckout, onCreatePR: onCreatePR, onArchive: onArchive)
            }
        }
    }
}

/// A branch row, styled to match `PullRequestChip`: frosted card, top-edge highlight, and a
/// trailing hover pill (blur scrim + staggered, scaling icon buttons). Archive asks for
/// confirmation in place before deleting.
private struct BranchChip: View {
    let branch: BranchInfo
    let onCheckout: (BranchInfo) -> Void
    let onCreatePR: (BranchInfo) -> Void
    let onArchive: (BranchInfo) -> Void

    @State private var isHovered = false
    @State private var confirmingArchive = false

    private static let hoverSpring: Animation = .spring(response: 0.3, dampingFraction: 0.7)

    var body: some View {
        textContent
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .trailing) { ChipBlurScrim(isHovered: isHovered) }
            .overlay(alignment: .trailing) { hoverActions.padding(.trailing, 10) }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .chipTopHighlight()
            .contentShape(Rectangle())
            .animation(Self.hoverSpring, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if !hovering { confirmingArchive = false }
            }
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(branch.name)
                .foregroundColor(.primary)
                .font(.system(size: 13))
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.tail)
            metaRow
        }
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            Text(verbatim: repoShortName).fixedSize()
            Text("·")
            Text(locationLabel)
            Spacer()
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    @ViewBuilder
    private var hoverActions: some View {
        if confirmingArchive {
            HStack(spacing: 4) {
                Text("Delete?").font(.system(size: 12)).foregroundStyle(.secondary)
                BranchIconButton(systemName: "checkmark", help: "Confirm delete", tint: .red) {
                    onArchive(branch)
                    confirmingArchive = false
                }
                BranchIconButton(systemName: "xmark", help: "Cancel") {
                    confirmingArchive = false
                }
            }
            .padding(.horizontal, 6)
        } else {
            // Indexed right-to-left so the stagger emanates from the trailing anchor: the
            // rightmost icon (index 0) pops in first, then cascades left.
            HStack(spacing: 4) {
                if branch.hasLocal {
                    BranchIconButton(systemName: "trash", help: "Archive (delete local branch)") {
                        confirmingArchive = true
                    }
                    .staggeredScale(isActive: isHovered, index: 2)
                }
                BranchIconButton(systemName: "wand.and.stars", help: "Draft a PR with Claude") {
                    onCreatePR(branch)
                }
                .staggeredScale(isActive: isHovered, index: 1)
                BranchIconButton(systemName: "arrow.down.circle", help: "Check out this branch locally") {
                    onCheckout(branch)
                }
                .staggeredScale(isActive: isHovered, index: 0)
            }
            .padding(.horizontal, 6)
            .scaleEffect(isHovered ? 1 : 0.7, anchor: .trailing)
            .opacity(isHovered ? 1 : 0)
        }
    }

    private var repoShortName: String {
        branch.repo.split(separator: "/").last.map(String.init) ?? branch.repo
    }

    private var locationLabel: String {
        if branch.hasLocal && branch.hasRemote { return "local + remote" }
        return branch.hasLocal ? "local" : "remote"
    }
}

/// An icon button matching the PR-row buttons: tap-bounce feedback plus the shared circular hover
/// effect. Uses SF Symbols (branch actions have no Octicon equivalents).
private struct BranchIconButton: View {
    let systemName: String
    let help: String
    var tint: Color = .primary
    let action: () -> Void
    @State private var tapTrigger = 0

    var body: some View {
        Button {
            tapTrigger += 1
            action()
        } label: {
            Image(systemName: systemName).tapBounce(tapTrigger)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .iconHoverEffect()
        .help(help)
    }
}
