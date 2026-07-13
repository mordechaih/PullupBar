# LocalDashboard

A macOS menubar app showing Claude Code usage %, active sessions
(context window %, running cost), and your open GitHub pull requests —
independent of any terminal statusline, so it works the same whether
Claude Code runs in a terminal or the desktop app.

## Build & run

    swift build
    swift run

## Test

    swift test

## Requirements

- macOS 13+
- `gh` CLI, authenticated (`gh auth login`), for the pull requests section
- Claude Code Keychain credentials present (`Claude Code-credentials`), for the usage section
