import Foundation
import Combine

@MainActor
final class DashboardStore: ObservableObject {
    @Published var pullRequests: [PullRequestInfo] = []
    @Published var prsUnavailable = false
    @Published var filter: PullRequestFilter = .open
    @Published var closedPullRequests: [PullRequestInfo] = []
    @Published var closedUnavailable = false
    @Published var closedLoaded = false
    @Published var noPRBranches: [BranchInfo] = []
    @Published var branchesUnavailable = false
    @Published var branchesLoaded = false

    let settings: SettingsStore

    private let processRunner: ProcessRunning
    private var refreshTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    /// The badge always reflects open PRs, regardless of which filter is being viewed.
    var badgeCount: Int { pullRequests.count }

    init(processRunner: ProcessRunning = SystemProcessRunner(), settings: SettingsStore = SettingsStore()) {
        self.processRunner = processRunner
        self.settings = settings

        // Restart polling when the interval changes so the new cadence takes effect immediately.
        settings.$pollIntervalSeconds
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.restartPolling() }
            }
            .store(in: &cancellables)
    }

    func refreshPullRequests() async {
        let runner = processRunner
        let result = await Task.detached(priority: .utility) { () -> [PullRequestInfo]? in
            fetchPullRequests(runner: runner, state: .open)
        }.value

        if let result {
            pullRequests = result
            prsUnavailable = false
        } else {
            prsUnavailable = true
        }
    }

    func refreshClosedPullRequests() async {
        let runner = processRunner
        let limit = settings.closedPRLimit
        let result = await Task.detached(priority: .utility) { () -> [PullRequestInfo]? in
            fetchPullRequests(runner: runner, state: .closed, closedLimit: limit)
        }.value

        closedLoaded = true
        if let result {
            closedPullRequests = result
            closedUnavailable = false
        } else {
            closedUnavailable = true
        }
    }

    /// Fetch branches without a PR. Decoupled from the poll timer — called on first panel
    /// appearance and on explicit refresh only.
    func refreshBranches() async {
        let runner = processRunner
        let roots = settings.repoSearchRoots
        let result = await Task.detached(priority: .utility) { () -> [BranchInfo]? in
            fetchBranchesWithoutPR(runner: runner, roots: roots)
        }.value

        branchesLoaded = true
        if let result {
            noPRBranches = result
            branchesUnavailable = false
        } else {
            branchesUnavailable = true
        }
    }

    /// Load branches once (first time the panel appears). Subsequent loads go through refresh.
    func loadBranchesIfNeeded() {
        guard !branchesLoaded else { return }
        Task { await refreshBranches() }
    }

    func refreshBranches_trigger() {
        Task { await refreshBranches() }
    }

    func checkoutBranch(_ branch: BranchInfo) {
        let runner = processRunner
        Task.detached(priority: .utility) { checkoutBranchLocally(branch, runner: runner) }
    }

    /// Delete the local branch, then drop it from the list so the row disappears without a reload.
    func archiveBranch(_ branch: BranchInfo) {
        let runner = processRunner
        Task {
            let ok = await Task.detached(priority: .utility) { archiveBranchLocally(branch, runner: runner) }.value
            if ok { noPRBranches.removeAll { $0.id == branch.id } }
        }
    }

    func createPRForBranch(_ branch: BranchInfo) {
        let runner = processRunner
        let command = settings.createPRCommand
        Task.detached(priority: .utility) { launchPRDraftSession(branch, command: command, runner: runner) }
    }

    /// Switch filters, loading closed PRs on first access to either the Merged or Closed tab
    /// (both are served by the same closed fetch).
    func selectFilter(_ newFilter: PullRequestFilter) {
        filter = newFilter
        if newFilter.isClosedTab && !closedLoaded {
            Task { await refreshClosedPullRequests() }
        }
    }

    /// Refresh whichever list is currently visible. Open PRs also refresh in the
    /// background poll, so the badge stays current even while viewing Merged/Closed.
    func refreshCurrentFilter() {
        switch filter {
        case .open: Task { await refreshPullRequests() }
        case .merged, .closed: Task { await refreshClosedPullRequests() }
        }
    }

    func checkoutPullRequest(_ pr: PullRequestInfo) {
        let runner = processRunner
        let roots = settings.repoSearchRoots
        Task.detached(priority: .utility) {
            checkoutPullRequestBranch(repo: pr.repo, number: pr.number, runner: runner, searchRoots: roots)
        }
    }

    func refreshAll() {
        Task { await refreshPullRequests() }
    }

    func startPolling() {
        guard refreshTimer == nil else { return }
        refreshAll()
        scheduleTimer()
    }

    private func scheduleTimer() {
        let interval = TimeInterval(max(10, settings.pollIntervalSeconds))
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshPullRequests() }
        }
    }

    /// Tear down and re-create the poll timer (e.g. after the interval setting changes).
    /// No-op until polling has started, so changing the setting before launch does nothing.
    func restartPolling() {
        guard refreshTimer != nil else { return }
        refreshTimer?.invalidate()
        refreshTimer = nil
        scheduleTimer()
    }
}
