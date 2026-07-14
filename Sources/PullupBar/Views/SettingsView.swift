import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
                terminalAppSection
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
            }

            folderList
        }
    }

    /// The folder rows and the "Add folder" button rendered as a single grouped list: rows sit flush
    /// against each other, separated by hairline dividers, with only the group's outer corners rounded.
    private var folderList: some View {
        VStack(spacing: 0) {
            ForEach(Array(settings.repoSearchRoots.enumerated()), id: \.element) { index, root in
                if index > 0 { rowDivider }
                folderRow(root)
            }
            if !settings.repoSearchRoots.isEmpty { rowDivider }
            addFolderRow
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(height: 1)
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
    }

    private var addFolderRow: some View {
        Button(action: addFolders) {
            HStack(spacing: 8) {
                Image(systemName: "plus").foregroundStyle(.secondary)
                Text("Add folder…").font(.system(size: 12))
                Spacer()
            }
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            Text("After checking out a PR or branch, also open a Claude Code session in the clone folder, using the terminal app below.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var terminalAppSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Terminal app").font(.system(size: 13, weight: .bold))
            Text("Opens the Claude Code sessions launched by \u{201C}Create PR\u{201D} and by \u{201C}Open Claude on checkout\u{201D}.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Menu {
                Button { settings.terminalAppPath = "" } label: {
                    appMenuLabel(name: "Terminal", path: "")
                }
                ForEach(TerminalApp.detectInstalled(), id: \.path) { app in
                    Button { settings.terminalAppPath = app.path } label: {
                        appMenuLabel(name: app.name, path: app.path)
                    }
                }
                Divider()
                Button("Choose app…") { chooseTerminalApp() }
            } label: {
                HStack {
                    Image(nsImage: TerminalApp.icon(forPath: settings.terminalAppPath))
                        .resizable().frame(width: 16, height: 16)
                    Text(terminalAppLabel)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
        }
    }

    /// A menu row pairing an app's Finder icon with its name.
    private func appMenuLabel(name: String, path: String) -> some View {
        Label {
            Text(name)
        } icon: {
            Image(nsImage: TerminalApp.icon(forPath: path))
                .resizable().frame(width: 16, height: 16)
        }
    }

    /// Display name for the current selection: empty means the system default (Terminal), otherwise
    /// the chosen `.app`'s name.
    private var terminalAppLabel: String {
        let path = settings.terminalAppPath
        guard !path.isEmpty else { return "Terminal" }
        return (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
    }

    private func chooseTerminalApp() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        panel.message = "Choose the terminal app to open Claude sessions in"
        if panel.runModal() == .OK, let url = panel.url {
            settings.terminalAppPath = url.path
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
