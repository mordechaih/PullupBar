# LocalDashboard

A macOS menubar app showing your open GitHub pull requests — CI status,
draft/review/conflict tags, and age, with the menu bar badge showing the
open PR count. Click a PR to open it on GitHub; hover a row to check out
its branch locally with one click.

## Build & run

From a terminal:

    swift build
    swift run

As a real app (double-click, Login Item, drag to Applications — no terminal needed to launch it afterward):

    ./Scripts/build-app.sh
    open .build/LocalDashboard.app

## Test

    swift test

## Requirements

- macOS 13+
- `gh` CLI, authenticated (`gh auth login`)
