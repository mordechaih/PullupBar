import Foundation

@MainActor
final class DashboardStore: ObservableObject {
    @Published var pullRequests: [PullRequestInfo] = []
    @Published var prsUnavailable = false
    @Published var filter: PullRequestFilter = .open
    @Published var closedPullRequests: [PullRequestInfo] = []
    @Published var closedUnavailable = false
    @Published var closedLoaded = false

    private let processRunner: ProcessRunning
    private var refreshTimer: Timer?

    /// The badge always reflects open PRs, regardless of which filter is being viewed.
    var badgeCount: Int { pullRequests.count }

    init(processRunner: ProcessRunning = SystemProcessRunner()) {
        self.processRunner = processRunner
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
        let result = await Task.detached(priority: .utility) { () -> [PullRequestInfo]? in
            fetchPullRequests(runner: runner, state: .closed)
        }.value

        closedLoaded = true
        if let result {
            closedPullRequests = result
            closedUnavailable = false
        } else {
            closedUnavailable = true
        }
    }

    /// Switch filters, loading closed PRs on first access to the Closed tab.
    func selectFilter(_ newFilter: PullRequestFilter) {
        filter = newFilter
        if newFilter == .closed && !closedLoaded {
            Task { await refreshClosedPullRequests() }
        }
    }

    /// Refresh whichever list is currently visible. Open PRs also refresh in the
    /// background poll, so the badge stays current even while viewing Closed.
    func refreshCurrentFilter() {
        switch filter {
        case .open: Task { await refreshPullRequests() }
        case .closed: Task { await refreshClosedPullRequests() }
        }
    }

    func checkoutPullRequest(_ pr: PullRequestInfo) {
        let runner = processRunner
        Task.detached(priority: .utility) {
            checkoutPullRequestBranch(repo: pr.repo, number: pr.number, runner: runner)
        }
    }

    func refreshAll() {
        Task { await refreshPullRequests() }
    }

    func startPolling() {
        guard refreshTimer == nil else { return }
        refreshAll()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshPullRequests() }
        }
    }
}
