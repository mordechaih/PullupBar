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

    /// Shell command run to open a terminal for a Claude session (Create PR, and checkout when
    /// `openClaudeOnCheckout` is on). `{script}` is replaced with the path to a generated
    /// `.command` script.
    @Published var createPRCommand: String {
        didSet { defaults.set(createPRCommand, forKey: Keys.createPRCommand) }
    }

    /// When true, checking out a PR or branch also opens a Claude Code session in the clone folder.
    @Published var openClaudeOnCheckout: Bool {
        didSet { defaults.set(openClaudeOnCheckout, forKey: Keys.openClaudeOnCheckout) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let repoSearchRoots = "repoSearchRoots"
        static let pollIntervalSeconds = "pollIntervalSeconds"
        static let closedPRLimit = "closedPRLimit"
        static let createPRCommand = "createPRCommand"
        static let openClaudeOnCheckout = "openClaudeOnCheckout"
    }

    static let defaultRepoSearchRoot = NSString(string: "~/Documents/GitHub").expandingTildeInPath
    static let defaultPollIntervalSeconds = 60
    static let defaultClosedPRLimit = 20
    static let defaultCreatePRCommand = "open {script}"

    static let pollIntervalOptions = [30, 60, 120, 300]
    static let closedPRLimitOptions = [10, 20, 50, 100]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.repoSearchRoots = (defaults.array(forKey: Keys.repoSearchRoots) as? [String]) ?? [Self.defaultRepoSearchRoot]
        let storedInterval = defaults.integer(forKey: Keys.pollIntervalSeconds)
        self.pollIntervalSeconds = storedInterval > 0 ? storedInterval : Self.defaultPollIntervalSeconds
        let storedLimit = defaults.integer(forKey: Keys.closedPRLimit)
        self.closedPRLimit = storedLimit > 0 ? storedLimit : Self.defaultClosedPRLimit
        let storedCommand = defaults.string(forKey: Keys.createPRCommand)
        self.createPRCommand = (storedCommand?.isEmpty == false) ? storedCommand! : Self.defaultCreatePRCommand
        self.openClaudeOnCheckout = defaults.bool(forKey: Keys.openClaudeOnCheckout)
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
