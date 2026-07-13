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
