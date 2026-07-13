import Foundation

func localRepoDirectory(
    forRepo repo: String,
    searchRoot: String = NSString(string: "~/Documents/GitHub").expandingTildeInPath,
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
) -> String? {
    guard let repoName = repo.split(separator: "/").last.map(String.init) else { return nil }
    let candidate = (searchRoot as NSString).appendingPathComponent(repoName)
    guard fileExists((candidate as NSString).appendingPathComponent(".git")) else { return nil }
    return candidate
}

@discardableResult
func checkoutPullRequestBranch(
    repo: String,
    number: Int,
    runner: ProcessRunning,
    localRepoDir: String? = nil
) -> Bool {
    guard let ghPath = resolveGHExecutablePath(runner: runner) else { return false }
    guard let repoDir = localRepoDir ?? localRepoDirectory(forRepo: repo) else { return false }
    return runner.run(ghPath, ["pr", "checkout", "\(number)", "--repo", repo], cwd: repoDir) != nil
}
