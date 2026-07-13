// Sources/PullupBar/Views/BranchesSectionView.swift
import SwiftUI

/// The "Branches without a PR" block rendered beneath the open-PR lanes. Owns its header
/// (title + count + refresh) and its loading / unavailable / empty / list states.
struct BranchesSectionView: View {
    let branches: [BranchInfo]
    let loaded: Bool
    let unavailable: Bool
    let onRefresh: () -> Void
    let onCheckout: (BranchInfo) -> Void
    let onCreatePR: (BranchInfo) -> Void
    let onArchive: (BranchInfo) -> Void

    @State private var refreshBounce = 0

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
            Button {
                refreshBounce += 1
                onRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .bounceOnValueChange(refreshBounce)
            }
            .buttonStyle(.plain)
            .help("Refresh branches")
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

private struct BranchChip: View {
    let branch: BranchInfo
    let onCheckout: (BranchInfo) -> Void
    let onCreatePR: (BranchInfo) -> Void
    let onArchive: (BranchInfo) -> Void

    @State private var isHovered = false
    @State private var confirmingArchive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(branch.name)
                .foregroundColor(.primary)
                .font(.system(size: 13)).fontWeight(.semibold)
                .lineLimit(1).truncationMode(.tail)
            metaRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .trailing) { actions.padding(.trailing, 10) }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if !hovering { confirmingArchive = false }
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
    private var actions: some View {
        if confirmingArchive {
            HStack(spacing: 8) {
                Text("Delete branch?").font(.system(size: 12)).foregroundStyle(.secondary)
                Button { onArchive(branch); confirmingArchive = false } label: {
                    Image(systemName: "checkmark").foregroundStyle(.red)
                }.buttonStyle(.plain).help("Confirm delete")
                Button { confirmingArchive = false } label: {
                    Image(systemName: "xmark").foregroundStyle(.secondary)
                }.buttonStyle(.plain).help("Cancel")
            }
            .padding(.horizontal, 6)
        } else if isHovered {
            HStack(spacing: 4) {
                if branch.hasLocal {
                    iconButton("trash", help: "Archive (delete local branch)") { confirmingArchive = true }
                }
                iconButton("wand.and.stars", help: "Draft a PR with Claude") { onCreatePR(branch) }
                if branch.hasLocal || branch.hasRemote {
                    iconButton("arrow.down.circle", help: "Check out this branch locally") { onCheckout(branch) }
                }
            }
            .padding(.horizontal, 6)
        }
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName).font(.system(size: 15))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var repoShortName: String {
        branch.repo.split(separator: "/").last.map(String.init) ?? branch.repo
    }

    private var locationLabel: String {
        if branch.hasLocal && branch.hasRemote { return "local + remote" }
        return branch.hasLocal ? "local" : "remote"
    }
}

private extension View {
    @ViewBuilder
    func bounceOnValueChange(_ value: Int) -> some View {
        if #available(macOS 14.0, *) { self.symbolEffect(.bounce, value: value) } else { self }
    }
}
