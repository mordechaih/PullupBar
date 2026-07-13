# Branches Without a PR — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Branches without a PR" section to the Open tab that lists local + remote git branches that never had a pull request, each with checkout, draft-PR-via-Claude, and archive (local delete) actions.

**Architecture:** All branch *listing* is done through local `git` in each clone discovered under the configured repo folders — no GitHub API for listing. The only `gh` call is a per-branch has-a-PR check. Fetching lives in pure, `ProcessRunning`-injectable functions mirroring `PullRequestFetcher`; state lives in `DashboardStore`, decoupled from the poll timer; UI is a new `BranchesSectionView` rendered beneath the open-PR lanes.

**Tech Stack:** Swift 5.9 / SwiftPM, SwiftUI + AppKit, XCTest. Shells out to `git` (`/usr/bin/git`) and `gh` via the existing `ProcessRunning` abstraction.

## Global Constraints

- macOS 13 or later; no new third-party dependencies.
- Shell out only through `ProcessRunning`; never call `Process` directly outside `SystemProcessRunner`.
- Resolve `gh` via the existing `resolveGHExecutablePath(runner:)`. Resolve `git` as `/usr/bin/git` (the standard macOS location / xcode-select shim), injectable as a `gitPath` parameter defaulting to `"/usr/bin/git"`.
- Pure functions take their dependencies as parameters (runner, path resolvers, directory-listing closures) so every one is unit-testable with a fake — follow the existing `PullRequestFetcher` / `PullRequestCheckout` style.
- Git subcommands target a repo with `-C <dir>` in the argument list (not `cwd`), so the args-only `run(_:_:)` overload carries everything and tests can assert on argv.
- User-facing copy uses "Branches without a PR" for the section and "Create PR" / "Checkout" / "Archive" for actions.
- Run tests with `swift test --filter <TestClass>`; build with `swift build`.

---

## File Structure

- Create: `Sources/PullupBar/Models/BranchInfo.swift` — `BranchInfo` struct, `BranchRef` + `parseBranchRefs`, `parseOriginURL`.
- Create: `Sources/PullupBar/Services/BranchFetcher.swift` — `CloneLocation`, `discoverClones`, `branchHasPR`, `fetchBranchesWithoutPR`.
- Create: `Sources/PullupBar/Services/BranchActions.swift` — `checkoutBranchLocally`, `archiveBranchLocally`, `prDraftScriptContents`, `launchPRDraftSession`.
- Create: `Sources/PullupBar/Views/BranchesSectionView.swift` — `BranchesSectionView` + `BranchChip`.
- Modify: `Sources/PullupBar/Services/SettingsStore.swift` — add `createPRCommand`.
- Modify: `Sources/PullupBar/Services/DashboardStore.swift` — branch state + refresh/checkout/archive/create-PR methods.
- Modify: `Sources/PullupBar/Views/PullRequestsSectionView.swift` — accept branch props, render `BranchesSectionView` under `openContent`.
- Modify: `Sources/PullupBar/Views/DashboardPanelView.swift` — wire store branch state + callbacks; trigger initial branch load; refresh branches from footer.
- Modify: `Sources/PullupBar/Views/SettingsView.swift` — add the create-PR command field.
- Create: `Tests/PullupBarTests/BranchInfoTests.swift`, `Tests/PullupBarTests/BranchFetcherTests.swift`, `Tests/PullupBarTests/BranchActionsTests.swift`.
- Modify: `Tests/PullupBarTests/DashboardStoreTests.swift` — branch-state coverage.

---

## Task 1: BranchInfo model + parsers

**Files:**
- Create: `Sources/PullupBar/Models/BranchInfo.swift`
- Test: `Tests/PullupBarTests/BranchInfoTests.swift`

**Interfaces:**
- Produces:
  - `struct BranchInfo: Identifiable, Sendable` with `let id, repo, name, localCloneDir: String`, `let hasLocal, hasRemote: Bool`, `let tipDate: Date?`.
  - `struct BranchRef: Sendable { let name: String; let authorEmail: String; let tipDate: Date? }`
  - `func parseBranchRefs(_ output: String) -> [BranchRef]` — parses tab-separated `name\t<email>\tunixtime` lines.
  - `func parseOriginURL(_ url: String) -> String?` — returns `"owner/repo"` from an ssh or https origin URL.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/PullupBarTests/BranchInfoTests.swift
import XCTest
@testable import PullupBar

final class BranchInfoTests: XCTestCase {
    func testParseOriginURLHandlesSSH() {
        XCTAssertEqual(parseOriginURL("git@github.com:owner/repo.git"), "owner/repo")
    }

    func testParseOriginURLHandlesHTTPS() {
        XCTAssertEqual(parseOriginURL("https://github.com/owner/repo.git\n"), "owner/repo")
    }

    func testParseOriginURLHandlesNoGitSuffix() {
        XCTAssertEqual(parseOriginURL("https://github.com/owner/repo"), "owner/repo")
    }

    func testParseOriginURLReturnsNilForGarbage() {
        XCTAssertNil(parseOriginURL(""))
        XCTAssertNil(parseOriginURL("not-a-url"))
    }

    func testParseBranchRefsSplitsFields() {
        let output = "feature-x\t<me@x.com>\t1700000000\nfeature-y\t<you@x.com>\t1700000100\n"
        let refs = parseBranchRefs(output)
        XCTAssertEqual(refs.count, 2)
        XCTAssertEqual(refs[0].name, "feature-x")
        XCTAssertEqual(refs[0].authorEmail, "me@x.com")
        XCTAssertEqual(refs[0].tipDate, Date(timeIntervalSince1970: 1700000000))
    }

    func testParseBranchRefsSkipsBlankAndMalformedLines() {
        let output = "\ngood\t<a@b.com>\t123\nmalformed-no-tabs\n"
        let refs = parseBranchRefs(output)
        XCTAssertEqual(refs.map(\.name), ["good"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter BranchInfoTests`
Expected: FAIL — `parseOriginURL` / `parseBranchRefs` / `BranchInfo` not defined.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/PullupBar/Models/BranchInfo.swift
import Foundation

struct BranchInfo: Identifiable, Sendable {
    let id: String          // "owner/repo@branch"
    let repo: String        // "owner/repo"
    let name: String        // branch name
    let localCloneDir: String
    let hasLocal: Bool
    let hasRemote: Bool
    let tipDate: Date?      // tip commit date, for newest-first sorting
}

struct BranchRef: Sendable {
    let name: String
    let authorEmail: String
    let tipDate: Date?
}

/// Parses `git for-each-ref` output formatted as `name\t<email>\tunixtime` (one ref per line).
/// Blank lines and lines without the two expected tabs are skipped. The email's angle brackets
/// are stripped; a non-numeric or missing timestamp yields a nil `tipDate`.
func parseBranchRefs(_ output: String) -> [BranchRef] {
    output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
        let parts = line.components(separatedBy: "\t")
        guard parts.count == 3 else { return nil }
        let name = parts[0].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let email = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        let date = TimeInterval(parts[2].trimmingCharacters(in: .whitespaces)).map { Date(timeIntervalSince1970: $0) }
        return BranchRef(name: name, authorEmail: email, tipDate: date)
    }
}

/// Extracts `owner/repo` from an origin remote URL, handling both
/// `git@github.com:owner/repo.git` and `https://github.com/owner/repo(.git)` forms.
func parseOriginURL(_ url: String) -> String? {
    var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return nil }
    if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
    // Normalize the ssh `host:owner/repo` form to `.../owner/repo`.
    if let colon = s.firstIndex(of: ":"), !s.contains("://") {
        s = String(s[s.index(after: colon)...])
    }
    let parts = s.split(separator: "/").map(String.init)
    guard parts.count >= 2 else { return nil }
    let repo = parts[parts.count - 1]
    let owner = parts[parts.count - 2]
    guard !owner.isEmpty, !repo.isEmpty, !owner.contains(".") else { return nil }
    return "\(owner)/\(repo)"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter BranchInfoTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/PullupBar/Models/BranchInfo.swift Tests/PullupBarTests/BranchInfoTests.swift
git commit -m "feat: add BranchInfo model and git ref/origin parsers"
```

---

## Task 2: Clone discovery + branch fetcher

**Files:**
- Create: `Sources/PullupBar/Services/BranchFetcher.swift`
- Test: `Tests/PullupBarTests/BranchFetcherTests.swift`

**Interfaces:**
- Consumes: `parseBranchRefs`, `parseOriginURL`, `BranchInfo`, `BranchRef` (Task 1); `ProcessRunning`, `resolveGHExecutablePath(runner:)` (existing).
- Produces:
  - `struct CloneLocation: Sendable { let repo: String; let dir: String }`
  - `func discoverClones(roots:runner:gitPath:subdirectories:) -> [CloneLocation]`
  - `func branchHasPR(repo:branch:runner:ghPath:) -> Bool`
  - `func fetchBranchesWithoutPR(runner:roots:gitPath:subdirectories:) -> [BranchInfo]?`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/PullupBarTests/BranchFetcherTests.swift
import XCTest
@testable import PullupBar

/// Answers git/gh calls from canned tables keyed by the distinctive argument.
private struct FakeBranchRunner: ProcessRunning {
    var email: String = "me@x.com"
    var originByDir: [String: String] = [:]        // dir -> origin URL
    var defaultBranchByDir: [String: String] = [:] // dir -> "origin/main"
    var localRefsByDir: [String: String] = [:]     // dir -> for-each-ref refs/heads output
    var remoteRefsByDir: [String: String] = [:]    // dir -> for-each-ref refs/remotes/origin output
    var prListByHead: [String: String] = [:]       // branch -> gh pr list json

    func run(_ path: String, _ args: [String]) -> String? {
        if args == ["-l", "-c", "command -v gh"] { return "/usr/bin/gh" }
        if args == ["config", "--get", "user.email"] { return email }
        if let ci = args.firstIndex(of: "-C"), ci + 1 < args.count {
            let dir = args[ci + 1]
            if args.contains("remote") { return originByDir[dir] }
            if args.contains("symbolic-ref") { return defaultBranchByDir[dir] }
            if args.contains("for-each-ref") {
                return args.contains("refs/heads") ? localRefsByDir[dir] : remoteRefsByDir[dir]
            }
        }
        if args.first == "pr", args.contains("list"), let hi = args.firstIndex(of: "--head"), hi + 1 < args.count {
            return prListByHead[args[hi + 1]] ?? "[]"
        }
        return nil
    }
}

final class BranchFetcherTests: XCTestCase {
    func testDiscoverClonesReadsOriginPerSubdir() {
        var runner = FakeBranchRunner()
        runner.originByDir = ["/root/a": "git@github.com:o/a.git", "/root/b": "not-a-repo"]
        let clones = discoverClones(
            roots: ["/root"], runner: runner,
            subdirectories: { _ in ["/root/a", "/root/b"] }
        )
        XCTAssertEqual(clones.map(\.repo), ["o/a"])
        XCTAssertEqual(clones.first?.dir, "/root/a")
    }

    func testFetchKeepsLocalBranchWithoutPRAndDropsDefaultAndPRBranches() {
        var runner = FakeBranchRunner()
        runner.originByDir = ["/root/a": "git@github.com:o/a.git"]
        runner.defaultBranchByDir = ["/root/a": "origin/main"]
        runner.localRefsByDir = ["/root/a": "main\t<me@x.com>\t100\nfeature\t<me@x.com>\t200\nhas-pr\t<me@x.com>\t150\n"]
        runner.remoteRefsByDir = ["/root/a": ""]
        runner.prListByHead = ["has-pr": #"[{"number":7}]"#, "feature": "[]"]

        let result = fetchBranchesWithoutPR(
            runner: runner, roots: ["/root"],
            subdirectories: { _ in ["/root/a"] }
        )

        XCTAssertEqual(result?.map(\.name), ["feature"])
        XCTAssertEqual(result?.first?.hasLocal, true)
        XCTAssertEqual(result?.first?.repo, "o/a")
    }

    func testFetchFiltersRemoteBranchesByAuthorEmail() {
        var runner = FakeBranchRunner(email: "me@x.com")
        runner.originByDir = ["/root/a": "git@github.com:o/a.git"]
        runner.defaultBranchByDir = ["/root/a": "origin/main"]
        runner.localRefsByDir = ["/root/a": ""]
        runner.remoteRefsByDir = ["/root/a":
            "mine\t<me@x.com>\t300\ntheirs\t<other@x.com>\t400\nHEAD\t<me@x.com>\t500\n"]

        let result = fetchBranchesWithoutPR(
            runner: runner, roots: ["/root"],
            subdirectories: { _ in ["/root/a"] }
        )

        XCTAssertEqual(result?.map(\.name), ["mine"])  // theirs filtered by email, HEAD skipped
        XCTAssertEqual(result?.first?.hasRemote, true)
    }

    func testFetchSortsByTipDateDescending() {
        var runner = FakeBranchRunner()
        runner.originByDir = ["/root/a": "git@github.com:o/a.git"]
        runner.defaultBranchByDir = ["/root/a": "origin/main"]
        runner.localRefsByDir = ["/root/a": "old\t<me@x.com>\t100\nnew\t<me@x.com>\t900\n"]
        runner.remoteRefsByDir = ["/root/a": ""]

        let result = fetchBranchesWithoutPR(
            runner: runner, roots: ["/root"],
            subdirectories: { _ in ["/root/a"] }
        )
        XCTAssertEqual(result?.map(\.name), ["new", "old"])
    }

    func testFetchReturnsNilWhenGHUnavailable() {
        struct NoGH: ProcessRunning { func run(_ p: String, _ a: [String]) -> String? { "" } }
        let result = fetchBranchesWithoutPR(
            runner: NoGH(), roots: ["/root"],
            subdirectories: { _ in ["/root/a"] }
        )
        XCTAssertNil(result)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter BranchFetcherTests`
Expected: FAIL — `discoverClones` / `fetchBranchesWithoutPR` not defined.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/PullupBar/Services/BranchFetcher.swift
import Foundation

struct CloneLocation: Sendable {
    let repo: String   // "owner/repo"
    let dir: String    // absolute path to the clone
}

private let defaultGitPath = "/usr/bin/git"

/// Lists directories one level under each root that contain a `.git` entry, expanding tildes.
private func defaultSubdirectories(_ root: String) -> [String] {
    let expanded = NSString(string: root).expandingTildeInPath
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(atPath: expanded) else { return [] }
    return entries.compactMap { entry in
        let dir = (expanded as NSString).appendingPathComponent(entry)
        let gitPath = (dir as NSString).appendingPathComponent(".git")
        return fm.fileExists(atPath: gitPath) ? dir : nil
    }
}

/// Discovers local clones under `roots`, reading each one's `owner/repo` from its origin remote.
/// `subdirectories` returns the candidate clone directories for a root (injected for tests).
func discoverClones(
    roots: [String],
    runner: ProcessRunning,
    gitPath: String = defaultGitPath,
    subdirectories: (String) -> [String] = defaultSubdirectories
) -> [CloneLocation] {
    var clones: [CloneLocation] = []
    var seen = Set<String>()
    for root in roots {
        for dir in subdirectories(root) {
            guard let origin = runner.run(gitPath, ["-C", dir, "remote", "get-url", "origin"]),
                  let repo = parseOriginURL(origin), !seen.contains(dir) else { continue }
            seen.insert(dir)
            clones.append(CloneLocation(repo: repo, dir: dir))
        }
    }
    return clones
}

/// True when `branch` has (or ever had) a PR in `repo`, in any state. A failed lookup is treated
/// as "has a PR" so a branch is never shown as PR-less on incomplete information.
func branchHasPR(repo: String, branch: String, runner: ProcessRunning, ghPath: String) -> Bool {
    guard let output = runner.run(ghPath, [
        "pr", "list", "--repo", repo, "--head", branch, "--state", "all", "--json", "number"
    ]), let data = output.data(using: .utf8),
       let items = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
        return true
    }
    return !items.isEmpty
}

/// Gathers local + remote branches without a PR across all discovered clones. Local branches are
/// always kept (minus the default branch); remote branches are kept only when their tip commit's
/// author email matches the user's `git config user.email`. Returns nil only when `gh` can't be
/// resolved at all (the feature is unavailable); an empty array means "none found".
func fetchBranchesWithoutPR(
    runner: ProcessRunning,
    roots: [String],
    gitPath: String = defaultGitPath,
    subdirectories: (String) -> [String] = defaultSubdirectories
) -> [BranchInfo]? {
    guard let ghPath = resolveGHExecutablePath(runner: runner) else { return nil }

    let myEmail = runner.run(gitPath, ["config", "--get", "user.email"])?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    var result: [BranchInfo] = []
    for clone in discoverClones(roots: roots, runner: runner, gitPath: gitPath, subdirectories: subdirectories) {
        let dir = clone.dir

        let defaultBranch = runner.run(gitPath, ["-C", dir, "symbolic-ref", "--short", "refs/remotes/origin/HEAD"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "origin/", with: "") ?? "main"

        let localOut = runner.run(gitPath, [
            "-C", dir, "for-each-ref",
            "--format=%(refname:lstrip=2)%09%(authoremail)%09%(committerdate:unix)", "refs/heads"
        ]) ?? ""
        let remoteOut = runner.run(gitPath, [
            "-C", dir, "for-each-ref",
            "--format=%(refname:lstrip=3)%09%(authoremail)%09%(committerdate:unix)", "refs/remotes/origin"
        ]) ?? ""

        // name -> (hasLocal, hasRemote, tipDate). Local refs seed the map; remote refs (author-filtered)
        // add/merge. HEAD and the default branch are never candidates.
        var byName: [String: (local: Bool, remote: Bool, date: Date?)] = [:]
        for ref in parseBranchRefs(localOut) where ref.name != defaultBranch && ref.name != "HEAD" {
            byName[ref.name] = (true, byName[ref.name]?.remote ?? false, ref.tipDate)
        }
        for ref in parseBranchRefs(remoteOut)
            where ref.name != defaultBranch && ref.name != "HEAD" && ref.authorEmail == myEmail {
            let existing = byName[ref.name]
            byName[ref.name] = (existing?.local ?? false, true, existing?.date ?? ref.tipDate)
        }

        for (name, flags) in byName where !branchHasPR(repo: clone.repo, branch: name, runner: runner, ghPath: ghPath) {
            result.append(BranchInfo(
                id: "\(clone.repo)@\(name)", repo: clone.repo, name: name,
                localCloneDir: dir, hasLocal: flags.local, hasRemote: flags.remote, tipDate: flags.date
            ))
        }
    }

    return result.sorted { ($0.tipDate ?? .distantPast) > ($1.tipDate ?? .distantPast) }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter BranchFetcherTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/PullupBar/Services/BranchFetcher.swift Tests/PullupBarTests/BranchFetcherTests.swift
git commit -m "feat: add clone discovery and no-PR branch fetcher"
```

---

## Task 3: Branch actions (checkout, archive, PR-draft launcher)

**Files:**
- Create: `Sources/PullupBar/Services/BranchActions.swift`
- Test: `Tests/PullupBarTests/BranchActionsTests.swift`

**Interfaces:**
- Consumes: `BranchInfo` (Task 1); `ProcessRunning`.
- Produces:
  - `@discardableResult func checkoutBranchLocally(_ branch: BranchInfo, runner:gitPath:) -> Bool`
  - `@discardableResult func archiveBranchLocally(_ branch: BranchInfo, runner:gitPath:) -> Bool`
  - `func prDraftScriptContents(dir:branch:prompt:) -> String`
  - `let prDraftPrompt: String`
  - `@discardableResult func launchPRDraftSession(_ branch: BranchInfo, command:runner:writeScript:) -> Bool`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/PullupBarTests/BranchActionsTests.swift
import XCTest
@testable import PullupBar

private final class ArgCapturingRunner: ProcessRunning, @unchecked Sendable {
    var lastPath: String?
    var lastArgs: [String]?
    let result: String?
    init(result: String? = "ok") { self.result = result }
    func run(_ path: String, _ args: [String]) -> String? {
        lastPath = path; lastArgs = args; return result
    }
}

private let sampleBranch = BranchInfo(
    id: "o/r@feature", repo: "o/r", name: "feature",
    localCloneDir: "/clones/r", hasLocal: true, hasRemote: false, tipDate: nil
)

final class BranchActionsTests: XCTestCase {
    func testCheckoutBuildsGitCheckoutArgv() {
        let runner = ArgCapturingRunner()
        XCTAssertTrue(checkoutBranchLocally(sampleBranch, runner: runner))
        XCTAssertEqual(runner.lastArgs, ["-C", "/clones/r", "checkout", "feature"])
    }

    func testArchiveBuildsForceDeleteArgv() {
        let runner = ArgCapturingRunner()
        XCTAssertTrue(archiveBranchLocally(sampleBranch, runner: runner))
        XCTAssertEqual(runner.lastArgs, ["-C", "/clones/r", "branch", "-D", "feature"])
    }

    func testArchiveReturnsFalseOnFailure() {
        let runner = ArgCapturingRunner(result: nil)
        XCTAssertFalse(archiveBranchLocally(sampleBranch, runner: runner))
    }

    func testScriptContentsCdChecksOutAndRunsClaude() {
        let script = prDraftScriptContents(dir: "/clones/r", branch: "feature", prompt: "do it")
        XCTAssertTrue(script.contains("cd \"/clones/r\""))
        XCTAssertTrue(script.contains("git checkout \"feature\""))
        XCTAssertTrue(script.contains("claude \"do it\""))
    }

    func testLaunchSubstitutesScriptPathAndRunsViaSh() {
        let runner = ArgCapturingRunner()
        var writtenTo: String?
        let ok = launchPRDraftSession(
            sampleBranch, command: "open -a iTerm {script}", runner: runner,
            writeScript: { _ in writtenTo = "/tmp/x.command"; return "/tmp/x.command" }
        )
        XCTAssertTrue(ok)
        XCTAssertEqual(writtenTo, "/tmp/x.command")
        XCTAssertEqual(runner.lastPath, "/bin/sh")
        XCTAssertEqual(runner.lastArgs, ["-c", "open -a iTerm /tmp/x.command"])
    }

    func testLaunchFailsWhenScriptCannotBeWritten() {
        let runner = ArgCapturingRunner()
        let ok = launchPRDraftSession(
            sampleBranch, command: "open {script}", runner: runner,
            writeScript: { _ in nil }
        )
        XCTAssertFalse(ok)
        XCTAssertNil(runner.lastArgs)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter BranchActionsTests`
Expected: FAIL — functions not defined.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/PullupBar/Services/BranchActions.swift
import Foundation

private let defaultGitPath = "/usr/bin/git"

/// The instruction handed to the Claude Code session opened by the Create-PR action.
let prDraftPrompt = "Review this branch's changes against the default branch and open a pull request with a clear title and description using the gh CLI."

/// Switches the clone to `branch`. For a remote-only branch, `git checkout <name>` creates a local
/// tracking branch from `origin/<name>` automatically.
@discardableResult
func checkoutBranchLocally(_ branch: BranchInfo, runner: ProcessRunning, gitPath: String = defaultGitPath) -> Bool {
    runner.run(gitPath, ["-C", branch.localCloneDir, "checkout", branch.name]) != nil
}

/// Force-deletes the local branch (`-D`). No-PR branches are typically unmerged, so a plain `-d`
/// would refuse; commits remain recoverable via reflog.
@discardableResult
func archiveBranchLocally(_ branch: BranchInfo, runner: ProcessRunning, gitPath: String = defaultGitPath) -> Bool {
    runner.run(gitPath, ["-C", branch.localCloneDir, "branch", "-D", branch.name]) != nil
}

/// The `.command` script body: enter the clone, check out the branch, then launch Claude Code.
func prDraftScriptContents(dir: String, branch: String, prompt: String) -> String {
    """
    #!/bin/sh
    cd "\(dir)" && git checkout "\(branch)" && claude "\(prompt)"
    """
}

/// Default: write the PR-draft script to a temp `.command` file and mark it executable.
/// Returns the file path, or nil if writing fails.
private func writePRDraftScript(_ contents: String) -> String? {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("pullupbar-createpr-\(UUID().uuidString).command")
    do {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    } catch {
        return nil
    }
}

/// Writes the PR-draft script, then runs the user's launch `command` (with `{script}` replaced by
/// the script path) through `/bin/sh -c`, so templates like `open {script}` or
/// `open -a iTerm {script}` work. `writeScript` is injected for tests.
@discardableResult
func launchPRDraftSession(
    _ branch: BranchInfo,
    command: String,
    runner: ProcessRunning,
    writeScript: (String) -> String? = writePRDraftScript
) -> Bool {
    let contents = prDraftScriptContents(dir: branch.localCloneDir, branch: branch.name, prompt: prDraftPrompt)
    guard let scriptPath = writeScript(contents) else { return false }
    let resolved = command.replacingOccurrences(of: "{script}", with: scriptPath)
    return runner.run("/bin/sh", ["-c", resolved]) != nil
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter BranchActionsTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/PullupBar/Services/BranchActions.swift Tests/PullupBarTests/BranchActionsTests.swift
git commit -m "feat: add branch checkout, archive, and PR-draft launcher"
```

---

## Task 4: Settings — create-PR command

**Files:**
- Modify: `Sources/PullupBar/Services/SettingsStore.swift`
- Test: `Tests/PullupBarTests/DashboardStoreTests.swift` (add a settings test here; the file already exercises the store/settings)

**Interfaces:**
- Produces: `SettingsStore.createPRCommand: String` (published, persisted), `SettingsStore.defaultCreatePRCommand: String`.

- [ ] **Step 1: Write the failing test**

First read the top of `Tests/PullupBarTests/DashboardStoreTests.swift` to match its style, then add:

```swift
func testCreatePRCommandDefaultsAndPersists() {
    let defaults = UserDefaults(suiteName: "createpr-\(UUID().uuidString)")!
    let a = SettingsStore(defaults: defaults)
    XCTAssertEqual(a.createPRCommand, SettingsStore.defaultCreatePRCommand)
    a.createPRCommand = "open -a iTerm {script}"
    let b = SettingsStore(defaults: defaults)
    XCTAssertEqual(b.createPRCommand, "open -a iTerm {script}")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DashboardStoreTests`
Expected: FAIL — `createPRCommand` not a member of `SettingsStore`.

- [ ] **Step 3: Write the implementation**

In `SettingsStore.swift` add the published property (after `closedPRLimit`):

```swift
    /// Shell command run to launch the Create-PR Claude session. `{script}` is replaced with the
    /// path to a generated `.command` script.
    @Published var createPRCommand: String {
        didSet { defaults.set(createPRCommand, forKey: Keys.createPRCommand) }
    }
```

Add to `Keys`:

```swift
        static let createPRCommand = "createPRCommand"
```

Add the default constant (next to the other defaults):

```swift
    static let defaultCreatePRCommand = "open {script}"
```

Initialize in `init` (after `closedPRLimit` is set):

```swift
        let storedCommand = defaults.string(forKey: Keys.createPRCommand)
        self.createPRCommand = (storedCommand?.isEmpty == false) ? storedCommand! : Self.defaultCreatePRCommand
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DashboardStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PullupBar/Services/SettingsStore.swift Tests/PullupBarTests/DashboardStoreTests.swift
git commit -m "feat: add configurable create-PR terminal command setting"
```

---

## Task 5: DashboardStore — branch state & actions

**Files:**
- Modify: `Sources/PullupBar/Services/DashboardStore.swift`
- Test: `Tests/PullupBarTests/DashboardStoreTests.swift`

**Interfaces:**
- Consumes: `fetchBranchesWithoutPR` (Task 2); `checkoutBranchLocally`, `archiveBranchLocally`, `launchPRDraftSession` (Task 3); `SettingsStore.createPRCommand` (Task 4).
- Produces on `DashboardStore`: `@Published var noPRBranches: [BranchInfo]`, `branchesLoaded: Bool`, `branchesUnavailable: Bool`; `func refreshBranches() async`; `func loadBranchesIfNeeded()`; `func checkoutBranch(_:)`; `func archiveBranch(_:)`; `func createPRForBranch(_:)`.

- [ ] **Step 1: Write the failing test**

Read the existing `DashboardStoreTests.swift` to reuse its fake runner pattern, then add a test that a successful fetch populates `noPRBranches` and marks it loaded. Match the existing async-store test style in that file; example shape:

```swift
@MainActor
func testRefreshBranchesPopulatesAndMarksLoaded() async {
    // A runner that reports one clone with a single no-PR local branch.
    let runner = BranchStoreFakeRunner()   // define locally, mirroring FakeBranchRunner from BranchFetcherTests
    let store = DashboardStore(processRunner: runner, settings: SettingsStore(defaults: UserDefaults(suiteName: "s-\(UUID().uuidString)")!))
    await store.refreshBranches()
    XCTAssertTrue(store.branchesLoaded)
    XCTAssertFalse(store.branchesUnavailable)
    XCTAssertEqual(store.noPRBranches.map(\.name), ["feature"])
}
```

Define `BranchStoreFakeRunner` in the test file with the same canned-table behavior as `FakeBranchRunner` in Task 2 (origin, symbolic-ref, for-each-ref refs/heads, gh pr list, `command -v gh`, `config --get user.email`), returning one clone `/root/a` → `o/a`, local refs `feature\t<me@x.com>\t200`, empty remote refs, `gh pr list --head feature` → `[]`, and `subdirectories` cannot be injected through the store — so have the runner also answer the FileManager-independent calls and point the settings' `repoSearchRoots` at a temp dir containing one real `.git` subdir. Simpler: create a temp directory tree in the test (`FileManager` mkdir `root/a/.git`) and set `settings.repoSearchRoots = [root]`, so `defaultSubdirectories` finds it; the runner answers the git/gh calls for `dir == root/a`.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DashboardStoreTests`
Expected: FAIL — `refreshBranches` / `noPRBranches` not defined.

- [ ] **Step 3: Write the implementation**

Add published state (after `closedLoaded`):

```swift
    @Published var noPRBranches: [BranchInfo] = []
    @Published var branchesUnavailable = false
    @Published var branchesLoaded = false
```

Add methods (after `refreshClosedPullRequests`):

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DashboardStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PullupBar/Services/DashboardStore.swift Tests/PullupBarTests/DashboardStoreTests.swift
git commit -m "feat: add branch state and actions to DashboardStore"
```

---

## Task 6: BranchesSectionView + BranchChip

**Files:**
- Create: `Sources/PullupBar/Views/BranchesSectionView.swift`

**Interfaces:**
- Consumes: `BranchInfo` (Task 1).
- Produces: `struct BranchesSectionView: View` with initializer parameters
  `branches: [BranchInfo]`, `loaded: Bool`, `unavailable: Bool`,
  `onRefresh: () -> Void`, `onCheckout: (BranchInfo) -> Void`,
  `onCreatePR: (BranchInfo) -> Void`, `onArchive: (BranchInfo) -> Void`.

There is no unit test for SwiftUI views (consistent with the existing codebase); verification is `swift build` plus the manual smoke test in Task 8.

- [ ] **Step 1: Write the view**

```swift
// Sources/PullupBar/Views/BranchesSectionView.swift
import SwiftUI
import AppKit

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
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Builds without errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/PullupBar/Views/BranchesSectionView.swift
git commit -m "feat: add BranchesSectionView and BranchChip"
```

---

## Task 7: Wire branches into the panel

**Files:**
- Modify: `Sources/PullupBar/Views/PullRequestsSectionView.swift`
- Modify: `Sources/PullupBar/Views/DashboardPanelView.swift`

**Interfaces:**
- Consumes: `BranchesSectionView` (Task 6); `DashboardStore` branch state + actions (Task 5).
- `PullRequestsSectionView` gains stored properties: `branches: [BranchInfo]`, `branchesLoaded: Bool`, `branchesUnavailable: Bool`, `onRefreshBranches: () -> Void`, `onCheckoutBranch: (BranchInfo) -> Void`, `onCreatePR: (BranchInfo) -> Void`, `onArchiveBranch: (BranchInfo) -> Void`.

- [ ] **Step 1: Add branch properties to PullRequestsSectionView**

After the existing `onCheckout` property (around line 12), add:

```swift
    let branches: [BranchInfo]
    let branchesLoaded: Bool
    let branchesUnavailable: Bool
    let onRefreshBranches: () -> Void
    let onCheckoutBranch: (BranchInfo) -> Void
    let onCreatePR: (BranchInfo) -> Void
    let onArchiveBranch: (BranchInfo) -> Void
```

- [ ] **Step 2: Render the branches section under `openContent`**

Replace the `openContent` computed property (lines 120-134) with:

```swift
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
```

- [ ] **Step 3: Pass branch state + callbacks from DashboardPanelView**

In `DashboardPanelView.swift`, extend the `PullRequestsSectionView(...)` call (after `onCheckout:`) with:

```swift
                    branches: store.noPRBranches,
                    branchesLoaded: store.branchesLoaded,
                    branchesUnavailable: store.branchesUnavailable,
                    onRefreshBranches: { store.refreshBranches_trigger() },
                    onCheckoutBranch: { store.checkoutBranch($0) },
                    onCreatePR: { store.createPRForBranch($0) },
                    onArchiveBranch: { store.archiveBranch($0) }
```

Since `refreshBranches()` is `async`, add a small sync trigger to `DashboardStore` (below `loadBranchesIfNeeded`):

```swift
    func refreshBranches_trigger() {
        Task { await refreshBranches() }
    }
```

- [ ] **Step 4: Trigger the first branch load when the panel appears**

In `DashboardPanelView.body`, add `.onAppear` to the outer `VStack` (the one ending `.frame(width: 380)`):

```swift
        .onAppear { store.loadBranchesIfNeeded() }
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: Builds without errors.

- [ ] **Step 6: Commit**

```bash
git add Sources/PullupBar/Views/PullRequestsSectionView.swift Sources/PullupBar/Views/DashboardPanelView.swift Sources/PullupBar/Services/DashboardStore.swift
git commit -m "feat: render branches-without-a-PR section under the Open tab"
```

---

## Task 8: Settings UI field + smoke test

**Files:**
- Modify: `Sources/PullupBar/Views/SettingsView.swift`

**Interfaces:**
- Consumes: `SettingsStore.createPRCommand` (Task 4).

- [ ] **Step 1: Add the create-PR command section**

In `SettingsView.body`, add `createPRCommandSection` to the `VStack` after `closedCountSection`:

```swift
                closedCountSection
                createPRCommandSection
```

Add the computed property (after `closedCountSection`):

```swift
    private var createPRCommandSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Create-PR terminal command").font(.system(size: 13, weight: .bold))
            Text("Runs when you click Create PR on a branch. {script} is replaced with a generated script that cds into the clone, checks out the branch, and launches Claude Code.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("open {script}", text: $settings.createPRCommand)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
    }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Builds without errors.

- [ ] **Step 3: Run the full test suite**

Run: `swift test`
Expected: All tests pass (existing + `BranchInfoTests`, `BranchFetcherTests`, `BranchActionsTests`, new `DashboardStoreTests`).

- [ ] **Step 4: Manual smoke test**

```bash
swift run
```

Verify:
1. The menu-bar panel's Open tab shows a "Branches without a PR" section beneath your open PRs, with a count and refresh button.
2. Branches you created locally (and remote branches you authored) that never had a PR appear; branches with any PR do not.
3. Hovering a row reveals Checkout, Create PR (wand), and — for local branches — Archive (trash). Archive asks "Delete branch?" before deleting; on confirm the row disappears.
4. Create PR opens the configured terminal, cds into the clone, checks out the branch, and starts Claude. Changing the command in Settings (e.g. `open -a iTerm {script}`) takes effect.

- [ ] **Step 5: Commit**

```bash
git add Sources/PullupBar/Views/SettingsView.swift
git commit -m "feat: add create-PR terminal command field to Settings"
```

---

## Self-Review Notes

- **Spec coverage:** scope/data source → Tasks 1–2; ownership filter (local kept, remote author-filtered, HEAD/default excluded) → Task 2; has-a-PR (any state) → `branchHasPR` Task 2; data model → Task 1; services → Tasks 2–3; store decoupled from poll → Task 5 (`loadBranchesIfNeeded`/`refreshBranches`, never in `scheduleTimer`); UI section + three actions + archive confirm → Tasks 6–7; create-PR launcher + `.command` script → Task 3; configurable terminal setting → Tasks 4 & 8; tests → Tasks 1–5.
- **Type consistency:** `BranchInfo` fields, `fetchBranchesWithoutPR`/`discoverClones`/`branchHasPR`, `checkoutBranchLocally`/`archiveBranchLocally`/`launchPRDraftSession`, and the `DashboardStore` method names are referenced identically across tasks.
- **No auto-fetch / no remote delete / fixed prompt** kept out of scope per the spec.
