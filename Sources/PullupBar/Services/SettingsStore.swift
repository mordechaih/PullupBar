import Foundation

/// User-configurable settings, persisted in `UserDefaults`. Published so views update live and
/// the store can react (e.g. restart polling) when a value changes. Only mutated from the UI
/// (main) thread.
final class SettingsStore: ObservableObject {
    /// Folders searched for a local clone when checking out a PR's branch. Absolute paths.
    @Published var repoSearchRoots: [String] {
        didSet { defaults.set(repoSearchRoots, forKey: Keys.repoSearchRoots) }
    }

    /// How often open PRs are polled, in seconds.
    @Published var pollIntervalSeconds: Int {
        didSet { defaults.set(pollIntervalSeconds, forKey: Keys.pollIntervalSeconds) }
    }

    /// Max closed PRs fetched per search (merged / closed-unmerged).
    @Published var closedPRLimit: Int {
        didSet { defaults.set(closedPRLimit, forKey: Keys.closedPRLimit) }
    }

    /// Path to the terminal `.app` agent sessions open in when the destination is a terminal.
    /// Empty string means the system default handler for `.command` scripts (Terminal). Non-empty
    /// is passed to `open -a <path>`. Shared by both agents, and kept while a desktop app is
    /// selected, so switching back restores the same terminal.
    @Published var terminalAppPath: String {
        didSet { defaults.set(terminalAppPath, forKey: Keys.terminalAppPath) }
    }

    /// The agent that Create PR and checkout (when `openAgentOnCheckout` is on) start.
    @Published var agent: CodingAgent {
        didSet { defaults.set(agent.rawValue, forKey: Keys.agent) }
    }

    /// When true, sessions open in the agent's desktop app instead of a terminal (if that app is
    /// installed; see `destination`).
    @Published var openInDesktopApp: Bool {
        didSet { defaults.set(openInDesktopApp, forKey: Keys.openInDesktopApp) }
    }

    /// When true, checking out a PR or branch also opens an agent session in the clone folder.
    @Published var openAgentOnCheckout: Bool {
        didSet { defaults.set(openAgentOnCheckout, forKey: Keys.openAgentOnCheckout) }
    }

    private let defaults: UserDefaults
    private let isDesktopAppInstalled: (CodingAgent) -> Bool

    private enum Keys {
        static let repoSearchRoots = "repoSearchRoots"
        static let pollIntervalSeconds = "pollIntervalSeconds"
        static let closedPRLimit = "closedPRLimit"
        static let terminalAppPath = "terminalAppPath"
        static let agent = "agent"
        static let openInDesktopApp = "openInDesktopApp"
        /// Predates Cursor support; kept so the saved value carries over.
        static let openAgentOnCheckout = "openClaudeOnCheckout"
    }

    static let defaultRepoSearchRoot = NSString(string: "~/Documents/GitHub").expandingTildeInPath
    static let defaultPollIntervalSeconds = 60
    static let defaultClosedPRLimit = 20

    static let pollIntervalOptions = [30, 60, 120, 300]
    static let closedPRLimitOptions = [10, 20, 50, 100]

    init(
        defaults: UserDefaults = .standard,
        isDesktopAppInstalled: @escaping (CodingAgent) -> Bool = { $0.desktopAppPath() != nil }
    ) {
        self.defaults = defaults
        self.isDesktopAppInstalled = isDesktopAppInstalled
        self.repoSearchRoots = (defaults.array(forKey: Keys.repoSearchRoots) as? [String]) ?? [Self.defaultRepoSearchRoot]
        let storedInterval = defaults.integer(forKey: Keys.pollIntervalSeconds)
        self.pollIntervalSeconds = storedInterval > 0 ? storedInterval : Self.defaultPollIntervalSeconds
        let storedLimit = defaults.integer(forKey: Keys.closedPRLimit)
        self.closedPRLimit = storedLimit > 0 ? storedLimit : Self.defaultClosedPRLimit
        self.terminalAppPath = defaults.string(forKey: Keys.terminalAppPath) ?? ""
        self.agent = defaults.string(forKey: Keys.agent).flatMap(CodingAgent.init(rawValue:)) ?? .claude
        self.openInDesktopApp = defaults.bool(forKey: Keys.openInDesktopApp)
        self.openAgentOnCheckout = defaults.bool(forKey: Keys.openAgentOnCheckout)
    }

    /// Where sessions open: the agent's desktop app when chosen and installed, otherwise the
    /// terminal app.
    var destination: AgentDestination {
        openInDesktopApp && isDesktopAppInstalled(agent) ? .desktopApp : .terminal(appPath: terminalAppPath)
    }

    /// Adds folders, skipping any already present (order preserved).
    func addRoots(_ paths: [String]) {
        var seen = Set(repoSearchRoots)
        for path in paths where !seen.contains(path) {
            repoSearchRoots.append(path)
            seen.insert(path)
        }
    }

    func removeRoot(_ path: String) {
        repoSearchRoots.removeAll { $0 == path }
    }
}
