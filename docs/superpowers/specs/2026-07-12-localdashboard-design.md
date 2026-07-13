# LocalDashboard — Design Spec

**Date:** 2026-07-12
**Repo:** `mordechaih/localdashboard` (public)

## Purpose

A macOS menubar app that surfaces the same "at a glance" info as the user's
Claude Code statusline script (`~/.claude/statusline-command.sh`), minus the
first line (cwd / git branch / model / effort — those are terminal-specific
and not meaningful outside an active shell prompt).

Motivation: the user is moving from Claude Code in a terminal to the Claude
Code desktop app. The statusline script only runs because Claude Code feeds
it live JSON on every terminal render; the desktop app doesn't have an
equivalent hook. LocalDashboard must source the same information
independently, in a way that works identically regardless of whether Claude
Code is running in a terminal or the desktop app.

## Tech Stack

Native SwiftUI `MenuBarExtra` app, targeting macOS 13+. No Electron, no
daemon, no dependency on the statusline script at all.

## Data Sources

### 1. Sessions (poll every 10s)

Read `~/.claude/sessions/*.json` — Claude Code's live session registry.
Each file contains: `pid`, `sessionId`, `cwd`, `name` (friendly derived
name), `status` (`busy`/`idle`), `startedAt`, `updatedAt`.

- Filter to sessions whose `pid` is still alive (liveness check).
- For each live session, locate its transcript at
  `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`.
- Parse the transcript's assistant messages for their `usage` blocks
  (`input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`,
  `output_tokens`).
- **Context window %**: latest message's cumulative token count (input +
  cache_read + cache_creation + output) ÷ the model's max context size
  (200K standard, 1M for `[1m]` model variants — inferred from the `model`
  field on the message).
- **Session cost**: running total across all assistant messages in the
  transcript, tokens × per-model pricing (separate rates for input, output,
  cache write, cache read).
- If a session's transcript file is missing or unreadable, skip that
  session silently (don't error the whole list).
- All active sessions are shown as a list (not collapsed to just one) —
  the user may have multiple sessions running (desktop + leftover
  terminal, multiple projects) at once.

### 2. Usage window (poll every 60s)

Same source the statusline script already uses: the Anthropic OAuth usage
endpoint (`https://api.anthropic.com/api/oauth/usage`), authenticated with
the OAuth token pulled from Keychain (`security find-generic-password -s
"Claude Code-credentials"`). Surfaces: usage percentage, $used / $limit,
and days until the monthly reset.

If the API call fails (offline, expired token), the Usage section shows an
inline "unavailable" state rather than blocking the rest of the panel.

### 3. Pull requests (poll every 60s)

`gh` search for open PRs authored by `@me`, across **all** repos (no cwd
scoping — a persistent menubar app has no "current directory"). Per PR:
number, title, CI status, draft/review/conflict state, age.

Same failure isolation as Usage: a failed `gh` call shows "unavailable"
for this section only.

## UI

### Menubar icon

Static icon with a small white badge (number cut out of a solid shape)
showing the **open PR count**. Badge omitted entirely when the count is 0.

### Panel (click to open)

A popover with three sections, stacked in this order:

1. **Usage window** — "big number block" layout: large percentage as the
   headline, progress bar underneath, a smaller secondary line with
   $used/$limit and days-to-reset. (Per-session cost lives in the Sessions
   section below, not duplicated here — there's no single "current"
   session once the panel lists all active ones.)
2. **Sessions** — "aligned columns" layout: a grid with one row per
   session — status dot | session name | inline bar + percentage | cost —
   columns aligned across all rows.
3. **Pull requests** — "statusline-style" layout: one line per PR — PR
   number + truncated title, then inline draft/review/conflict tags, then
   a CI status dot, with the age pinned to the far right of the row.

A manual refresh control sits in the panel footer in addition to the
automatic polling described above.

## Error Handling

- Dead session PIDs are filtered out before rendering, not shown as
  errored rows.
- Missing/unreadable transcript files cause that one session to be
  skipped, not an error state for the whole Sessions section.
- Failed Usage or PR API calls degrade only their own section to an
  "unavailable" inline state; the rest of the panel keeps working.

## Repo Setup

- New public GitHub repo: `mordechaih/localdashboard`.
- Standard Swift/Xcode project structure.
- MIT license, basic README.
- `.gitignore` for Xcode/Swift build artifacts (`.build/`, `*.xcodeproj/xcuserdata`, `DerivedData/`, etc).

## Out of Scope (v1)

- No settings UI.
- No launch-at-login toggle.
- No system notifications.
- No historical charts/trends — current-state snapshot only.
