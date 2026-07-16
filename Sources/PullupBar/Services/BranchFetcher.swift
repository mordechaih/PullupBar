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

/// The set of branch head names for which the user has (or ever had) a PR in `repo`, in any
/// state — fetched in one `gh pr list` call instead of one lookup per branch. Scoped to
/// `--author @me`: the No-PR list only ever considers the user's own branches (remote ones are
/// already filtered to the user's email), so the user's PRs are the only ones that matter, and
/// scoping keeps the payload tiny on large repos. It's also more correct than listing every PR
/// under a fixed limit, which would truncate on repos with thousands of PRs and could miss the
/// user's own older PR. Returns nil on a failed or malformed lookup so the caller can treat every
/// branch conservatively (as if it has a PR) and never show a branch as PR-less on incomplete
/// information.
func prHeadRefs(repo: String, runner: ProcessRunning, ghPath: String) -> Set<String>? {
    guard let output = runner.run(ghPath, [
        "pr", "list", "--repo", repo, "--author", "@me", "--state", "all", "--limit", "500", "--json", "headRefName"
    ]), let data = output.data(using: .utf8),
       let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        return nil
    }
    return Set(items.compactMap { $0["headRefName"] as? String })
}

/// Gathers local + remote branches without a PR across all discovered clones. Local branches are
/// always kept (minus the default branch); remote branches are kept only when their tip commit's
/// author email matches the user's `git config user.email`. Returns nil only when `gh` can't be
/// resolved at all (the feature is unavailable); an empty array means "none found".
func fetchBranchesWithoutPR(
    runner: ProcessRunning,
    roots: [String],
    gitPath: String = defaultGitPath,
    subdirectories: (String) -> [String] = defaultSubdirectories,
    fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
    pathCache: GHPathCache = .shared
) -> [BranchInfo]? {
    guard let ghPath = pathCache.path(runner: runner, fileExists: fileExists) else { return nil }

    let myEmail = runner.run(gitPath, ["config", "--get", "user.email"])?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    // Each clone's git reads and PR lookup are independent, so process clones concurrently.
    let clones = discoverClones(roots: roots, runner: runner, gitPath: gitPath, subdirectories: subdirectories)
    let perClone = runConcurrently(clones.map { clone in
        { branchesWithoutPR(for: clone, runner: runner, gitPath: gitPath, ghPath: ghPath, myEmail: myEmail) }
    })

    return perClone.flatMap { $0 }
        .sorted { ($0.tipDate ?? .distantPast) > ($1.tipDate ?? .distantPast) }
}

/// PR-less branches for a single clone. Fetches the repo's PR head refs once, then keeps local
/// branches (minus the default branch) and author-matched remote branches whose name isn't among
/// them. A failed PR lookup (`prHeadRefs` == nil) drops every branch — never surface a branch as
/// PR-less on incomplete information.
private func branchesWithoutPR(
    for clone: CloneLocation,
    runner: ProcessRunning,
    gitPath: String,
    ghPath: String,
    myEmail: String
) -> [BranchInfo] {
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

    let headsWithPR = prHeadRefs(repo: clone.repo, runner: runner, ghPath: ghPath)
    return byName.compactMap { name, flags in
        // nil lookup -> treat as "has PR" (exclude); otherwise exclude names that have a PR.
        guard let headsWithPR, !headsWithPR.contains(name) else { return nil }
        return BranchInfo(
            id: "\(clone.repo)@\(name)@\(dir)", repo: clone.repo, name: name,
            localCloneDir: dir, hasLocal: flags.local, hasRemote: flags.remote, tipDate: flags.date
        )
    }
}
