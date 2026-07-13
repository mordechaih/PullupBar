import SwiftUI
import AppKit

/// The settings panel shown in place of the PR list when the footer gear is tapped. Fixed to the
/// same width/height as `PullRequestsSectionView` so toggling never resizes the hosting window.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let maxContentHeight: CGFloat

    private static let width: CGFloat = 380
    private var fixedHeight: CGFloat { min(420, maxContentHeight) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Settings").font(.headline)
                repoFoldersSection
                refreshIntervalSection
                closedCountSection
                openClaudeOnCheckoutSection
                terminalCommandSection
            }
            .padding(16)
            .frame(width: Self.width, alignment: .leading)
        }
        .frame(width: Self.width, height: fixedHeight)
    }

    private var repoFoldersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repository folders").font(.system(size: 13, weight: .bold))
            Text("Folders PullupBar searches for a local clone when you check out a PR's branch.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if settings.repoSearchRoots.isEmpty {
                Text("No folders added — checkout is disabled until you add one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(settings.repoSearchRoots, id: \.self) { root in
                    folderRow(root)
                }
            }

            Button(action: addFolders) {
                Label("Add folder…", systemImage: "plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
    }

    private func folderRow(_ root: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder").foregroundStyle(.secondary)
            Text(abbreviated(root))
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(root)
            Spacer()
            Button {
                settings.removeRoot(root)
            } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove folder")
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private var refreshIntervalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Refresh interval").font(.system(size: 13, weight: .bold))
            Picker("", selection: $settings.pollIntervalSeconds) {
                ForEach(SettingsStore.pollIntervalOptions, id: \.self) { seconds in
                    Text(intervalLabel(seconds)).tag(seconds)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private var closedCountSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Closed PRs shown").font(.system(size: 13, weight: .bold))
            Picker("", selection: $settings.closedPRLimit) {
                ForEach(SettingsStore.closedPRLimitOptions, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private var openClaudeOnCheckoutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $settings.openClaudeOnCheckout) {
                Text("Open Claude on checkout").font(.system(size: 13, weight: .bold))
            }
            Text("After checking out a PR or branch, also open a Claude Code session in the clone folder, using the terminal command below.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var terminalCommandSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Terminal command").font(.system(size: 13, weight: .bold))
            Text("Opens the Claude Code sessions launched by Create PR and by \u{201C}Open Claude on checkout\u{201D}. {script} is replaced with a generated script that cds into the clone and launches Claude Code.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("open {script}", text: $settings.createPRCommand)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
    }

    private func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders that contain your local repository clones"
        if panel.runModal() == .OK {
            settings.addRoots(panel.urls.map { $0.path })
        }
    }

    private func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    private func intervalLabel(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m"
    }
}
