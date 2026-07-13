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
    subdirectories: (String) -> [String] = defaultSubdirectories,
    fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
) -> [BranchInfo]? {
    guard let ghPath = resolveGHExecutablePath(runner: runner, fileExists: fileExists) else { return nil }

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
                id: "\(clone.repo)@\(name)@\(dir)", repo: clone.repo, name: name,
                localCloneDir: dir, hasLocal: flags.local, hasRemote: flags.remote, tipDate: flags.date
            ))
        }
    }

    return result.sorted { ($0.tipDate ?? .distantPast) > ($1.tipDate ?? .distantPast) }
}
