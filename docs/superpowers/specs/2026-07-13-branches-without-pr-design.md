# Branches Without a PR — Design

## Summary

Add a "Branches without a PR" section to PullupBar's Open tab, surfacing
git branches — local and remote — that have never had a pull request (open,
merged, or closed). This targets the "I pushed work but forgot to open a PR"
case. Each branch row supports three quick actions: check out the branch
locally, launch a Claude Code session that drafts a PR, and archive
(delete) the local branch.

## Scope & Data Source

The repo set is discovered by **enumerating git clones one level deep under
the configured `repoSearchRoots`**. For each clone, `owner/repo` is read from
`git remote get-url origin`. This surfaces branches even in repos where the
user has no PRs.

All branch *listing* is done through local git — no GitHub API calls:

- **Local branches:** `git for-each-ref refs/heads`, minus the default branch.
  All are kept (a local branch is implicitly "yours").
- **Remote branches:** `git for-each-ref refs/remotes/origin` including the tip
  commit's author email; kept only when that email matches
  `git config user.email`. Uses the clone's **last-fetched state** — no
  automatic `git fetch`. This is fast and works offline, but may miss branches
  pushed to the remote since the user's last fetch.

A branch present both locally and remotely collapses into a single entry,
flagged as both (`hasLocal` and `hasRemote`).

The only `gh` invocation is the **has-a-PR check**, run once per surviving
candidate:

```
gh pr list --repo owner/repo --head <branch> --state all --json number
```

An empty result means the branch has never had a PR and is included. Candidate
counts are expected to be small, so this stays cheap.

## Data Model

New `Models/BranchInfo.swift`:

```swift
struct BranchInfo: Identifiable, Sendable {
    let id: String          // "owner/repo@branch"
    let repo: String        // "owner/repo"
    let name: String        // branch name
    let localCloneDir: String
    let hasLocal: Bool
    let hasRemote: Bool
    let tipDate: Date?      // tip commit date, for newest-first sorting
}
```

Parse helpers for the `for-each-ref` output live next to the existing PR
parsers so they are unit-tested the same way.

## Services

**New `Services/BranchFetcher.swift`** — pure functions taking a
`ProcessRunning`, mirroring `PullRequestFetcher`'s style:

- `discoverClones(roots:runner:)` → `[(repo: String, dir: String)]` —
  enumerate one level deep under each root, read the origin remote, derive
  `owner/repo`.
- `fetchBranchesWithoutPR(runner:roots:myEmail:)` → `[BranchInfo]?` — run the
  `for-each-ref` queries per clone, apply the ownership filter, run the
  per-branch has-a-PR check, return survivors sorted by `tipDate` descending.

**New `Services/BranchActions.swift`**:

- `checkoutBranch(_:runner:)` — check out the branch in its local clone.
- `archiveBranch(_:runner:)` — `git branch -D <branch>` in the local clone.
  Force-delete is required because no-PR branches are typically unmerged;
  commits remain recoverable via reflog. Applies only to entries with a local
  branch.
- `launchPRDraftSession(_:launchCommand:runner:)` — see Actions below.

## Store & Loading

`DashboardStore` gains:

- `@Published var noPRBranches: [BranchInfo] = []`
- `@Published var branchesLoaded = false`
- `@Published var branchesUnavailable = false`

Loading is **decoupled from the poll timer** so the Open tab's 60s cadence
stays cheap:

- `refreshBranches()` runs the fetch on a detached utility task (same pattern
  as `refreshClosedPullRequests`), reading `myEmail` from
  `git config user.email` inside the fetcher.
- Triggered **once when the panel first appears** and on an explicit **manual
  refresh** of the branches section — never on the poll.
- `checkoutBranch(_:)` and `archiveBranch(_:)` run detached. On success,
  `archiveBranch` removes the entry from `noPRBranches` in-place so the row
  disappears without a full reload.

## UI

Under the Open tab, beneath the open-PR list, a **"Branches without a PR"**
section with a collapsible header showing a count and a small refresh button.

Each **branch row** shows: branch name, `owner/repo`, a local/remote
indicator, and three actions styled to match the existing PR-row affordances:

- **Checkout** — reuses `checkoutBranch`; disabled if no local clone dir.
- **Create PR** — writes a temp executable `.command` script, then runs the
  configured launch command (see Actions).
- **Archive** — `git branch -D`; shown only when `hasLocal`. Requires a
  confirm click: the row swaps to an "Archive? ✓ ✗" affordance before the
  delete runs.

Empty and unavailable states mirror the PR section (e.g. "No branches without
a PR", and a note when `gh`/git is unavailable).

## Actions: Create-PR Launcher

The Create-PR action drafts a PR through a Claude Code terminal session:

1. Write a temp executable `.command` script:
   ```sh
   cd "<localCloneDir>" && git checkout "<branch>" && claude "<prompt>"
   ```
2. Run the configured launch command with the `{script}` placeholder
   substituted for the script path.

The prompt is a fixed default asking Claude to review the branch's diff against
the default branch and open a pull request.

## Settings

One new field in `SettingsStore`, persisted in `UserDefaults` alongside the
existing keys:

- **"Create-PR terminal command"** — text, default `open {script}` (opens the
  `.command` in Terminal.app). Users can set e.g. `open -a iTerm {script}` to
  use a different terminal. A short helper line in `SettingsView` explains the
  `{script}` placeholder.

## Testing

- **`BranchFetcherTests`** — clone discovery, `for-each-ref` output parsing,
  the ownership filter (remote branches filtered by author email; local
  branches always kept), and has-a-PR exclusion.
- **`BranchActionsTests`** — `checkoutBranch`, `archiveBranch`, and the
  Create-PR launcher each build the correct argv / script contents.

Both use the existing fake `ProcessRunning`, following current test patterns.

## Out of Scope (YAGNI)

- Automatic `git fetch` before listing remote branches.
- Configurable Create-PR prompt text.
- Remote-branch deletion or the tag-then-delete archive variants.
- Showing branches for repos not cloned under the configured roots.
