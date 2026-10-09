import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The settings panel shown in place of the PR list when the footer gear is tapped. Fixed to the
/// same width/height as `PullRequestsSectionView` so toggling never resizes the hosting window.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let maxContentHeight: CGFloat

    /// Mirrors the system login-item state. Not persisted here — `SMAppService` is the source of
    /// truth, so we read it on appear and write through on change.
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    private static let width: CGFloat = DashboardMetrics.panelWidth
    private var fixedHeight: CGFloat { min(420, maxContentHeight) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Settings").font(.headline)
                repoFoldersSection
                refreshIntervalSection
                closedCountSection
                launchAtLoginSection
                openAgentOnCheckoutSection
                agentSection
                openInSection
            }
            .padding(16)
            .frame(width: Self.width, alignment: .leading)
        }
        .frame(width: Self.width, height: fixedHeight)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $launchAtLogin) {
                Text("Launch at login").font(.system(size: 13, weight: .bold))
            }
            .onChange(of: launchAtLogin) { newValue in
                // Revert to the actual system state if register/unregister failed.
                if !LaunchAtLogin.setEnabled(newValue) {
                    launchAtLogin = LaunchAtLogin.isEnabled
                }
            }
            Text("Start PullupBar automatically when you log in to your Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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

    private var openAgentOnCheckoutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $settings.openAgentOnCheckout) {
                Text("Open agent on checkout").font(.system(size: 13, weight: .bold))
            }
            Text("After checking out a PR or branch, also open \(settings.agent.displayName) in the clone folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agent").font(.system(size: 13, weight: .bold))
            Picker("", selection: $settings.agent) {
                ForEach(CodingAgent.allCases, id: \.self) { agent in
                    Text(agent.displayName).tag(agent)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    /// One menu for where sessions open: the agent's desktop app (when installed) above a divider,
    /// then the terminals and "Choose terminal app…" as one group.
    private var openInSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Open in").font(.system(size: 13, weight: .bold))
            Text("Used by \u{201C}Create PR\u{201D} and by \u{201C}Open agent on checkout\u{201D}.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Menu {
                if let appPath = settings.agent.desktopAppPath() {
                    Button { settings.openInDesktopApp = true } label: {
                        appMenuLabel(name: settings.agent.desktopAppName, path: appPath)
                    }
                    Divider()
                }
                Button { selectTerminal("") } label: {
                    appMenuLabel(name: "Terminal", path: "")
                }
                ForEach(TerminalApp.detectInstalled(), id: \.path) { app in
                    Button { selectTerminal(app.path) } label: {
                        appMenuLabel(name: app.name, path: app.path)
                    }
                }
                Button { chooseTerminalApp() } label: {
                    Label {
                        Text("Choose terminal app…")
                    } icon: {
                        Image(nsImage: TerminalApp.symbolIcon("plus"))
                    }
                }
            } label: {
                HStack {
                    Image(nsImage: selectedTargetIcon)
                        .resizable().frame(width: 16, height: 16)
                    Text(selectedTargetLabel)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
                .padding(8)
                .contentShape(Rectangle())
            }
            // A plain button-style menu draws the label as laid out (full width, own chevron), so
            // the whole row is clickable; `.borderlessButton` would collapse it to a compact control.
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            // Same grouped-list look as the repository folders above.
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            if let install = missingCLIInstallCommand {
                (Text("The \(settings.agent.displayName) CLI isn\u{2019}t installed. Run ")
                    + Text(install).font(.system(.caption, design: .monospaced))
                    + Text(" in a terminal, then try again."))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The install command to show when sessions open in a terminal and the agent's CLI (for agents
    /// PullupBar checks) isn't installed; nil otherwise.
    private var missingCLIInstallCommand: String? {
        guard case .terminal = settings.destination,
              let install = settings.agent.cliInstallCommand,
              !isCLIInstalled(settings.agent) else { return nil }
        return install
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

    private func selectTerminal(_ path: String) {
        settings.terminalAppPath = path
        settings.openInDesktopApp = false
    }

    private var selectedTargetIcon: NSImage {
        if case .desktopApp = settings.destination, let appPath = settings.agent.desktopAppPath() {
            return TerminalApp.icon(forPath: appPath)
        }
        return TerminalApp.icon(forPath: settings.terminalAppPath)
    }

    /// Display name for the current selection: the agent's desktop app, or for a terminal, empty
    /// means the system default (Terminal), otherwise the chosen `.app`'s name.
    private var selectedTargetLabel: String {
        if case .desktopApp = settings.destination { return settings.agent.desktopAppName }
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
        panel.message = "Choose the terminal app to open agent sessions in"
        if panel.runModal() == .OK, let url = panel.url {
            selectTerminal(url.path)
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
