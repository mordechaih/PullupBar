# LocalDashboard Menubar App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a native macOS menubar app (`LocalDashboard`) that shows Claude Code usage %, active sessions (context %, cost), and open GitHub PRs — sourced independently of the terminal statusline, so it works identically whether Claude Code runs in a terminal or the desktop app.

**Architecture:** A single SwiftUI `MenuBarExtra` scene backed by one `@MainActor` `ObservableObject` (`DashboardStore`) that polls three independent data sources (session registry + transcripts, Anthropic usage API, `gh` CLI) on their own timers and publishes per-section state, including per-section "unavailable" flags so one failing source never blocks the others. All non-trivial parsing/business logic lives in pure, synchronously-testable free functions; I/O (subprocess, Keychain, network) is behind small protocols so it can be faked in tests.

**Tech Stack:** Swift Package Manager executable target (macOS 13+), SwiftUI `MenuBarExtra`, Foundation `Process`/`Pipe` for subprocess calls, `URLSession` for the usage API, XCTest.

## Global Constraints

- macOS 13.0+ deployment target (`MenuBarExtra` requires it).
- Swift Package Manager project (`Package.swift`), **not** a full `.xcodeproj` — this deviates from the design spec's literal "standard Swift/Xcode project structure" phrase, but was chosen deliberately: it keeps the whole TDD loop on `swift build` / `swift test` (matching every prototype already validated in this session), avoids `.xcodeproj` merge-conflict-prone XML, and still produces a real, launchable native macOS app. Note this to the user if it comes up.
- No third-party dependencies. Foundation + SwiftUI + AppKit only.
- No Electron, no daemon process, no dependency on `~/.claude/statusline-command.sh`.
- All polling: sessions every 10s, Usage API + PRs every 60s (per spec).
- Errors are isolated per-section: dead PIDs are filtered silently, missing transcripts skip that one session, failed Usage/PR fetches degrade only their own section to "unavailable" — never the whole panel.
- Repo: public GitHub repo `mordechaih/localdashboard`. MIT license, copyright holder "Mordechai Hammer" (from local git config).
- Panel section order: Usage → Sessions → Pull Requests. Layouts: Usage = "big number block", Sessions = "aligned columns", Pull Requests = "statusline-style" — one line per PR: truncated title, inline draft/review/conflict tags, CI dot, age pinned to the far right (per user's mockup selections, PR layout revised mid-implementation to match the original bash statusline's single-line format).
- Menubar badge: PR count, shown as a solid white shape with the number cut out (transparent) of it; badge is omitted entirely (falls back to a plain icon) when the PR count is 0.

---

## File Structure

```
Package.swift
.gitignore
LICENSE
README.md
Sources/LocalDashboard/
  LocalDashboardApp.swift          # @main App, MenuBarExtra scene, badge icon rendering
  Models/
    ModelPricing.swift             # pricing table, TokenUsage, cost(), contextUsedPercent()
    TranscriptReader.swift         # JSONL parsing -> TranscriptSnapshot
    SessionRegistry.swift          # SessionInfo, isPidAlive, loadSessions
    SessionRow.swift                # SessionRow, computeSessionRows (combines registry+transcript)
    UsageWindowInfo.swift          # UsageWindowInfo, parseUsageWindowResponse
    PullRequestInfo.swift          # PullRequestInfo, parseSearchResults, enrichPullRequest
  Services/
    ProcessRunner.swift            # ProcessRunning protocol + SystemProcessRunner
    KeychainTokenProvider.swift    # KeychainTokenProviding protocol + KeychainTokenProvider
    PullRequestFetcher.swift       # fetchPullRequests(runner:) — two-step gh fetch
    UsageWindowFetcher.swift       # fetchUsageWindow(tokenProvider:dataTask:) — API call
    DashboardStore.swift           # ObservableObject aggregating all three sources
  Views/
    UsageSectionView.swift
    SessionsSectionView.swift
    PullRequestsSectionView.swift
    DashboardPanelView.swift
Tests/LocalDashboardTests/
  ModelPricingTests.swift
  TranscriptReaderTests.swift
  SessionRegistryTests.swift
  SessionRowTests.swift
  UsageWindowInfoTests.swift
  PullRequestInfoTests.swift
  ProcessRunnerTests.swift
  PullRequestFetcherTests.swift
  UsageWindowFetcherTests.swift
  DashboardStoreTests.swift
```

---

### Task 1: Project Scaffold + GitHub Repo

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `LICENSE`
- Create: `README.md`
- Create: `Sources/LocalDashboard/LocalDashboardApp.swift`

**Interfaces:**
- Produces: an `executableTarget` named `LocalDashboard` and a `testTarget` named `LocalDashboardTests` that later tasks add files/tests into.

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LocalDashboard",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "LocalDashboard",
            path: "Sources/LocalDashboard"
        ),
        .testTarget(
            name: "LocalDashboardTests",
            dependencies: ["LocalDashboard"],
            path: "Tests/LocalDashboardTests"
        )
    ]
)
```

- [ ] **Step 2: Create `.gitignore`**

```
.build/
.swiftpm/
DerivedData/
*.xcodeproj/xcuserdata/
.DS_Store
```

- [ ] **Step 3: Create `LICENSE` (MIT)**

```
MIT License

Copyright (c) 2026 Mordechai Hammer

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 4: Create `README.md`**

```markdown
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
```

- [ ] **Step 5: Create minimal working `LocalDashboardApp.swift`**

```swift
import SwiftUI

@main
struct LocalDashboardApp: App {
    var body: some Scene {
        MenuBarExtra("LocalDashboard", systemImage: "gauge.medium") {
            Text("LocalDashboard")
                .padding()
        }
    }
}
```

- [ ] **Step 6: Verify it builds and runs**

Run: `swift build`
Expected: `Build complete!` with no errors.

Run: `swift run &` then check the menu bar for a gauge icon, then stop it (`kill %1` or Ctrl-C).
Expected: A gauge icon appears in the menu bar; clicking it shows "LocalDashboard" text.

- [ ] **Step 7: Commit and create the GitHub repo**

```bash
git add Package.swift .gitignore LICENSE README.md Sources/
git commit -m "Scaffold LocalDashboard SwiftPM menubar app"
gh repo create mordechaih/localdashboard --public --source=. --remote=origin
git push -u origin main
```

Expected: repo created at `https://github.com/mordechaih/localdashboard`, `main` pushed.

---

### Task 2: ModelPricing

**Files:**
- Create: `Sources/LocalDashboard/Models/ModelPricing.swift`
- Test: `Tests/LocalDashboardTests/ModelPricingTests.swift`

**Interfaces:**
- Produces: `struct ModelPricing { let contextWindow: Int; let inputPerMTok: Double; let outputPerMTok: Double; static func forModel(_ model: String) -> ModelPricing }`, `struct TokenUsage: Sendable { let model: String; let inputTokens: Int; let cacheCreationInputTokens: Int; let cacheReadInputTokens: Int; let outputTokens: Int }`, `func cost(for usage: TokenUsage) -> Double`, `func contextUsedPercent(model: String, totalContextTokens: Int) -> Int`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import LocalDashboard

final class ModelPricingTests: XCTestCase {
    func testSonnetCostAndPercent() {
        let usage = TokenUsage(
            model: "claude-sonnet-5",
            inputTokens: 2,
            cacheCreationInputTokens: 67,
            cacheReadInputTokens: 67535,
            outputTokens: 1301
        )
        XCTAssertEqual(cost(for: usage), 0.040032750000000006, accuracy: 0.0000001)
        XCTAssertEqual(
            contextUsedPercent(model: usage.model, totalContextTokens: 2 + 67 + 67535 + 1301),
            7
        )
    }

    func testOpusCostAndPercent() {
        let usage = TokenUsage(
            model: "claude-opus-4-8",
            inputTokens: 100_000,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 500_000,
            outputTokens: 20_000
        )
        XCTAssertEqual(cost(for: usage), 1.25, accuracy: 0.0000001)
        XCTAssertEqual(contextUsedPercent(model: usage.model, totalContextTokens: 620_000), 62)
    }

    func testHaikuHasSmallerContextWindow() {
        XCTAssertEqual(ModelPricing.forModel("claude-haiku-4-5").contextWindow, 200_000)
    }

    func testPercentClampsAt100() {
        XCTAssertEqual(contextUsedPercent(model: "claude-sonnet-5", totalContextTokens: 2_000_000), 100)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ModelPricingTests`
Expected: FAIL — `cannot find 'TokenUsage' in scope` (or similar; the type doesn't exist yet).

- [ ] **Step 3: Implement `ModelPricing.swift`**

```swift
import Foundation

struct ModelPricing {
    let contextWindow: Int
    let inputPerMTok: Double
    let outputPerMTok: Double

    static func forModel(_ model: String) -> ModelPricing {
        let m = model.lowercased()
        if m.contains("opus") {
            return ModelPricing(contextWindow: 1_000_000, inputPerMTok: 5.0, outputPerMTok: 25.0)
        } else if m.contains("haiku") {
            return ModelPricing(contextWindow: 200_000, inputPerMTok: 1.0, outputPerMTok: 5.0)
        } else {
            return ModelPricing(contextWindow: 1_000_000, inputPerMTok: 3.0, outputPerMTok: 15.0)
        }
    }
}

struct TokenUsage: Sendable {
    let model: String
    let inputTokens: Int
    let cacheCreationInputTokens: Int
    let cacheReadInputTokens: Int
    let outputTokens: Int
}

func cost(for usage: TokenUsage) -> Double {
    let pricing = ModelPricing.forModel(usage.model)
    let inputCost = Double(usage.inputTokens) / 1_000_000 * pricing.inputPerMTok
    let cacheWriteCost = Double(usage.cacheCreationInputTokens) / 1_000_000 * pricing.inputPerMTok * 1.25
    let cacheReadCost = Double(usage.cacheReadInputTokens) / 1_000_000 * pricing.inputPerMTok * 0.1
    let outputCost = Double(usage.outputTokens) / 1_000_000 * pricing.outputPerMTok
    return inputCost + cacheWriteCost + cacheReadCost + outputCost
}

func contextUsedPercent(model: String, totalContextTokens: Int) -> Int {
    let pricing = ModelPricing.forModel(model)
    let pct = Double(totalContextTokens) / Double(pricing.contextWindow) * 100
    return min(100, Int(pct.rounded()))
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ModelPricingTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalDashboard/Models/ModelPricing.swift Tests/LocalDashboardTests/ModelPricingTests.swift
git commit -m "Add ModelPricing: per-model rates, cost, and context-percent calculation"
```

---

### Task 3: TranscriptReader

**Files:**
- Create: `Sources/LocalDashboard/Models/TranscriptReader.swift`
- Test: `Tests/LocalDashboardTests/TranscriptReaderTests.swift`

**Interfaces:**
- Consumes: `TokenUsage`, `cost(for:)` from Task 2.
- Produces: `struct TranscriptSnapshot: Sendable { let model: String; let contextTokens: Int; let totalCostUSD: Double }`, `func encodedProjectDir(forCwd cwd: String) -> String`, `func parseTranscript(atPath path: String) -> TranscriptSnapshot?`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import LocalDashboard

final class TranscriptReaderTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testParseTranscriptSumsCostAndTracksLatestUsage() throws {
        let lines = [
            #"{"type":"user","message":{}}"#,
            #"{"type":"assistant","message":{"model":"claude-sonnet-5","usage":{"input_tokens":10,"cache_creation_input_tokens":5,"cache_read_input_tokens":100,"output_tokens":50}}}"#,
            #"{"type":"assistant","message":{"model":"claude-sonnet-5","usage":{"input_tokens":20,"cache_creation_input_tokens":0,"cache_read_input_tokens":200,"output_tokens":80}}}"#
        ]
        let path = tempDir.appendingPathComponent("session.jsonl")
        try lines.joined(separator: "\n").write(to: path, atomically: true, encoding: .utf8)

        let snapshot = parseTranscript(atPath: path.path)

        XCTAssertEqual(snapshot?.model, "claude-sonnet-5")
        XCTAssertEqual(snapshot?.contextTokens, 20 + 0 + 200 + 80)

        let expectedCost =
            cost(for: TokenUsage(model: "claude-sonnet-5", inputTokens: 10, cacheCreationInputTokens: 5, cacheReadInputTokens: 100, outputTokens: 50))
            + cost(for: TokenUsage(model: "claude-sonnet-5", inputTokens: 20, cacheCreationInputTokens: 0, cacheReadInputTokens: 200, outputTokens: 80))
        XCTAssertEqual(snapshot?.totalCostUSD ?? -1, expectedCost, accuracy: 0.00000001)
    }

    func testMissingFileReturnsNil() {
        let missing = tempDir.appendingPathComponent("nope.jsonl").path
        XCTAssertNil(parseTranscript(atPath: missing))
    }

    func testEncodedProjectDirReplacesSlashesWithDashes() {
        XCTAssertEqual(
            encodedProjectDir(forCwd: "/Users/mordechaihammer/Documents/GitHub/LocalDashboard"),
            "-Users-mordechaihammer-Documents-GitHub-LocalDashboard"
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TranscriptReaderTests`
Expected: FAIL — `cannot find 'parseTranscript' in scope`.

- [ ] **Step 3: Implement `TranscriptReader.swift`**

```swift
import Foundation

struct UsageBlock: Decodable {
    let input_tokens: Int
    let cache_creation_input_tokens: Int?
    let cache_read_input_tokens: Int?
    let output_tokens: Int
}

struct AssistantMessage: Decodable {
    let model: String?
    let usage: UsageBlock?
}

struct TranscriptEntry: Decodable {
    let type: String
    let message: AssistantMessage?
}

struct TranscriptSnapshot: Sendable {
    let model: String
    let contextTokens: Int
    let totalCostUSD: Double
}

func encodedProjectDir(forCwd cwd: String) -> String {
    cwd.replacingOccurrences(of: "/", with: "-")
}

func parseTranscript(atPath path: String) -> TranscriptSnapshot? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    guard let text = String(data: data, encoding: .utf8) else { return nil }

    var latestUsage: UsageBlock?
    var latestModel: String?
    var totalCost = 0.0
    let decoder = JSONDecoder()

    for line in text.split(separator: "\n") {
        guard let lineData = line.data(using: .utf8) else { continue }
        guard let entry = try? decoder.decode(TranscriptEntry.self, from: lineData) else { continue }
        guard entry.type == "assistant", let msg = entry.message, let usage = msg.usage, let model = msg.model else { continue }

        latestUsage = usage
        latestModel = model
        totalCost += cost(for: TokenUsage(
            model: model,
            inputTokens: usage.input_tokens,
            cacheCreationInputTokens: usage.cache_creation_input_tokens ?? 0,
            cacheReadInputTokens: usage.cache_read_input_tokens ?? 0,
            outputTokens: usage.output_tokens
        ))
    }

    guard let usage = latestUsage, let model = latestModel else { return nil }
    let contextTokens = usage.input_tokens
        + (usage.cache_creation_input_tokens ?? 0)
        + (usage.cache_read_input_tokens ?? 0)
        + usage.output_tokens

    return TranscriptSnapshot(model: model, contextTokens: contextTokens, totalCostUSD: totalCost)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TranscriptReaderTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalDashboard/Models/TranscriptReader.swift Tests/LocalDashboardTests/TranscriptReaderTests.swift
git commit -m "Add TranscriptReader: parse Claude Code JSONL transcripts for usage/cost"
```

---

### Task 4: SessionRegistry

**Files:**
- Create: `Sources/LocalDashboard/Models/SessionRegistry.swift`
- Test: `Tests/LocalDashboardTests/SessionRegistryTests.swift`

**Interfaces:**
- Produces: `struct SessionInfo: Codable, Sendable { let pid: Int; let sessionId: String; let cwd: String; let name: String?; let status: String }`, `func isPidAlive(_ pid: Int) -> Bool`, `func loadSessions(sessionsDir: String, isAlive: (Int) -> Bool = isPidAlive) -> [SessionInfo]`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import LocalDashboard

final class SessionRegistryTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func writeSession(pid: Int, sessionId: String, cwd: String, name: String, status: String) throws {
        let json = #"{"pid":\#(pid),"sessionId":"\#(sessionId)","cwd":"\#(cwd)","name":"\#(name)","status":"\#(status)"}"#
        try json.write(to: tempDir.appendingPathComponent("\(sessionId).json"), atomically: true, encoding: .utf8)
    }

    func testLoadSessionsFiltersDeadPids() throws {
        try writeSession(pid: 111, sessionId: "alive-1", cwd: "/tmp/a", name: "alive", status: "busy")
        try writeSession(pid: 222, sessionId: "dead-1", cwd: "/tmp/b", name: "dead", status: "idle")

        let sessions = loadSessions(sessionsDir: tempDir.path, isAlive: { $0 == 111 })

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.sessionId, "alive-1")
    }

    func testLoadSessionsIgnoresNonJSONFiles() throws {
        try writeSession(pid: 333, sessionId: "alive-2", cwd: "/tmp/c", name: "alive2", status: "busy")
        try "not a session".write(to: tempDir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let sessions = loadSessions(sessionsDir: tempDir.path, isAlive: { _ in true })

        XCTAssertEqual(sessions.count, 1)
    }

    func testIsPidAliveDetectsDefinitelyDeadPid() {
        XCTAssertFalse(isPidAlive(999_999))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SessionRegistryTests`
Expected: FAIL — `cannot find 'loadSessions' in scope`.

- [ ] **Step 3: Implement `SessionRegistry.swift`**

```swift
import Foundation

struct SessionInfo: Codable, Sendable {
    let pid: Int
    let sessionId: String
    let cwd: String
    let name: String?
    let status: String
}

func isPidAlive(_ pid: Int) -> Bool {
    kill(pid_t(pid), 0) == 0
}

func loadSessions(sessionsDir: String, isAlive: (Int) -> Bool = isPidAlive) -> [SessionInfo] {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(atPath: sessionsDir) else { return [] }

    var result: [SessionInfo] = []
    let decoder = JSONDecoder()
    for file in files where file.hasSuffix(".json") {
        let path = (sessionsDir as NSString).appendingPathComponent(file)
        guard let data = fm.contents(atPath: path) else { continue }
        guard let info = try? decoder.decode(SessionInfo.self, from: data) else { continue }
        if isAlive(info.pid) {
            result.append(info)
        }
    }
    return result
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SessionRegistryTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalDashboard/Models/SessionRegistry.swift Tests/LocalDashboardTests/SessionRegistryTests.swift
git commit -m "Add SessionRegistry: read ~/.claude/sessions/*.json, filter dead pids"
```

---

### Task 5: SessionRow

**Files:**
- Create: `Sources/LocalDashboard/Models/SessionRow.swift`
- Test: `Tests/LocalDashboardTests/SessionRowTests.swift`

**Interfaces:**
- Consumes: `contextUsedPercent(model:totalContextTokens:)` (Task 2); `parseTranscript(atPath:)`, `encodedProjectDir(forCwd:)`, `TranscriptSnapshot` (Task 3); `SessionInfo`, `loadSessions(sessionsDir:isAlive:)`, `isPidAlive(_:)` (Task 4).
- Produces: `struct SessionRow: Identifiable, Sendable { let id: String; let name: String; let status: String; let contextPercent: Int; let costUSD: Double }`, `func computeSessionRows(sessionsDir: String, projectsDir: String, isAlive: (Int) -> Bool = isPidAlive) -> [SessionRow]`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import LocalDashboard

final class SessionRowTests: XCTestCase {
    var sessionsDir: URL!
    var projectsDir: URL!
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        sessionsDir = root.appendingPathComponent("sessions")
        projectsDir = root.appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testComputeSessionRowsCombinesRegistryAndTranscript() throws {
        let cwd = "/tmp/my-project"
        let sessionId = "sess-1"
        try #"{"pid":333,"sessionId":"\#(sessionId)","cwd":"\#(cwd)","name":"my-project","status":"busy"}"#
            .write(to: sessionsDir.appendingPathComponent("\(sessionId).json"), atomically: true, encoding: .utf8)

        let projectDir = projectsDir.appendingPathComponent(encodedProjectDir(forCwd: cwd))
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let transcriptLine = #"{"type":"assistant","message":{"model":"claude-sonnet-5","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":90,"output_tokens":50}}}"#
        try transcriptLine.write(to: projectDir.appendingPathComponent("\(sessionId).jsonl"), atomically: true, encoding: .utf8)

        let rows = computeSessionRows(sessionsDir: sessionsDir.path, projectsDir: projectsDir.path, isAlive: { $0 == 333 })

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, sessionId)
        XCTAssertEqual(rows.first?.name, "my-project")
        XCTAssertEqual(rows.first?.status, "busy")
        XCTAssertEqual(rows.first?.contextPercent, 0) // (10+0+90+50)/1_000_000 rounds to 0
    }

    func testSessionSkippedWhenTranscriptMissing() throws {
        let cwd = "/tmp/no-transcript"
        let sessionId = "sess-2"
        try #"{"pid":444,"sessionId":"\#(sessionId)","cwd":"\#(cwd)","name":"no-transcript","status":"idle"}"#
            .write(to: sessionsDir.appendingPathComponent("\(sessionId).json"), atomically: true, encoding: .utf8)

        let rows = computeSessionRows(sessionsDir: sessionsDir.path, projectsDir: projectsDir.path, isAlive: { $0 == 444 })

        XCTAssertEqual(rows.count, 0)
    }

    func testDeadSessionFilteredBeforeTranscriptLookup() throws {
        let sessionId = "sess-3"
        try #"{"pid":555,"sessionId":"\#(sessionId)","cwd":"/tmp/x","name":"dead","status":"idle"}"#
            .write(to: sessionsDir.appendingPathComponent("\(sessionId).json"), atomically: true, encoding: .utf8)

        let rows = computeSessionRows(sessionsDir: sessionsDir.path, projectsDir: projectsDir.path, isAlive: { _ in false })

        XCTAssertEqual(rows.count, 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SessionRowTests`
Expected: FAIL — `cannot find 'computeSessionRows' in scope`.

- [ ] **Step 3: Implement `SessionRow.swift`**

```swift
import Foundation

struct SessionRow: Identifiable, Sendable {
    let id: String
    let name: String
    let status: String
    let contextPercent: Int
    let costUSD: Double
}

func computeSessionRows(
    sessionsDir: String,
    projectsDir: String,
    isAlive: (Int) -> Bool = isPidAlive
) -> [SessionRow] {
    let sessions = loadSessions(sessionsDir: sessionsDir, isAlive: isAlive)

    var rows: [SessionRow] = []
    for session in sessions {
        let encodedDir = encodedProjectDir(forCwd: session.cwd)
        let transcriptPath = "\(projectsDir)/\(encodedDir)/\(session.sessionId).jsonl"
        guard let snapshot = parseTranscript(atPath: transcriptPath) else { continue }

        let percent = contextUsedPercent(model: snapshot.model, totalContextTokens: snapshot.contextTokens)
        rows.append(SessionRow(
            id: session.sessionId,
            name: session.name ?? session.sessionId,
            status: session.status,
            contextPercent: percent,
            costUSD: snapshot.totalCostUSD
        ))
    }
    return rows
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SessionRowTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalDashboard/Models/SessionRow.swift Tests/LocalDashboardTests/SessionRowTests.swift
git commit -m "Add SessionRow: combine session registry + transcript into display rows"
```

---

### Task 6: UsageWindowInfo

**Files:**
- Create: `Sources/LocalDashboard/Models/UsageWindowInfo.swift`
- Test: `Tests/LocalDashboardTests/UsageWindowInfoTests.swift`

**Interfaces:**
- Produces: `struct UsageWindowInfo: Sendable { let usedUSD: Double; let limitUSD: Double; let usedPercent: Int }`, `func parseUsageWindowResponse(_ data: Data) -> UsageWindowInfo?`.

This mirrors the statusline script's jq fallback chain exactly: try `extra_usage`, then `five_hour`, then `seven_day`; `used_credits`/100 and `monthly_limit`/100 (both stored as cents), `utilization` floored to an Int percent.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import LocalDashboard

final class UsageWindowInfoTests: XCTestCase {
    func testParsesExtraUsageBucket() {
        let json = #"{"extra_usage":{"used_credits":1234,"monthly_limit":10000,"utilization":45.7}}"#
        let info = parseUsageWindowResponse(json.data(using: .utf8)!)

        XCTAssertEqual(info?.usedUSD ?? -1, 12.34, accuracy: 0.001)
        XCTAssertEqual(info?.limitUSD ?? -1, 100.0, accuracy: 0.001)
        XCTAssertEqual(info?.usedPercent, 45)
    }

    func testFallsBackToFiveHourWhenExtraUsageMissing() {
        let json = #"{"five_hour":{"used_credits":500,"monthly_limit":2000,"utilization":25.0}}"#
        let info = parseUsageWindowResponse(json.data(using: .utf8)!)

        XCTAssertEqual(info?.usedUSD ?? -1, 5.0, accuracy: 0.001)
    }

    func testFallsBackToSevenDayWhenOthersMissing() {
        let json = #"{"seven_day":{"used_credits":700,"monthly_limit":3000,"utilization":10.9}}"#
        let info = parseUsageWindowResponse(json.data(using: .utf8)!)

        XCTAssertEqual(info?.usedPercent, 10) // floor, not round
    }

    func testReturnsNilWhenNoBucketsPresent() {
        XCTAssertNil(parseUsageWindowResponse("{}".data(using: .utf8)!))
    }

    func testReturnsNilOnMalformedJSON() {
        XCTAssertNil(parseUsageWindowResponse("not json".data(using: .utf8)!))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter UsageWindowInfoTests`
Expected: FAIL — `cannot find 'parseUsageWindowResponse' in scope`.

- [ ] **Step 3: Implement `UsageWindowInfo.swift`**

```swift
import Foundation

struct UsageWindowInfo: Sendable {
    let usedUSD: Double
    let limitUSD: Double
    let usedPercent: Int
}

private struct UsageWindowBucket: Decodable {
    let used_credits: Double?
    let monthly_limit: Double?
    let utilization: Double?
}

private struct UsageAPIResponse: Decodable {
    let extra_usage: UsageWindowBucket?
    let five_hour: UsageWindowBucket?
    let seven_day: UsageWindowBucket?
}

func parseUsageWindowResponse(_ data: Data) -> UsageWindowInfo? {
    guard let response = try? JSONDecoder().decode(UsageAPIResponse.self, from: data) else { return nil }
    guard let bucket = response.extra_usage ?? response.five_hour ?? response.seven_day else { return nil }
    guard let usedCredits = bucket.used_credits,
          let monthlyLimit = bucket.monthly_limit,
          let utilization = bucket.utilization else { return nil }

    return UsageWindowInfo(
        usedUSD: usedCredits / 100,
        limitUSD: monthlyLimit / 100,
        usedPercent: Int(utilization.rounded(.down))
    )
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter UsageWindowInfoTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalDashboard/Models/UsageWindowInfo.swift Tests/LocalDashboardTests/UsageWindowInfoTests.swift
git commit -m "Add UsageWindowInfo: parse Anthropic usage API fallback chain"
```

---

### Task 7: PullRequestInfo

**Files:**
- Create: `Sources/LocalDashboard/Models/PullRequestInfo.swift`
- Test: `Tests/LocalDashboardTests/PullRequestInfoTests.swift`

**Interfaces:**
- Produces: `struct PullRequestInfo: Identifiable, Sendable { let id: Int; let number: Int; let title: String; let url: String; let repo: String; let isDraft: Bool; let createdAt: Date; var ciStatus: String; var reviewDecision: String?; var isConflicting: Bool; var ageDays: Int { get } }`, `func parseSearchResults(_ data: Data) -> [PullRequestInfo]`, `func enrichPullRequest(_ pr: PullRequestInfo, withDetailJSON data: Data) -> PullRequestInfo`.

This mirrors the statusline script's two jq passes: the global `gh search prs` list (number/title/url/isDraft/repository/createdAt) doesn't support `statusCheckRollup`/`reviewDecision`/`mergeable` — those come from a **second**, per-PR `gh pr view --repo <repo> <number>` call, confirmed by hand against a real PR earlier in this session.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import LocalDashboard

final class PullRequestInfoTests: XCTestCase {
    private func makePR(json: String) -> PullRequestInfo {
        parseSearchResults(json.data(using: .utf8)!)[0]
    }

    func testParseSearchResults() {
        let json = """
        [
          {
            "number": 3665,
            "title": "Add new button variant",
            "url": "https://github.com/lyft/LyftProductLanguage/pull/3665",
            "isDraft": false,
            "repository": {"nameWithOwner": "lyft/LyftProductLanguage"},
            "createdAt": "2026-06-01T12:00:00Z"
          }
        ]
        """
        let prs = parseSearchResults(json.data(using: .utf8)!)

        XCTAssertEqual(prs.count, 1)
        XCTAssertEqual(prs[0].number, 3665)
        XCTAssertEqual(prs[0].repo, "lyft/LyftProductLanguage")
        XCTAssertEqual(prs[0].ciStatus, "PENDING")
        XCTAssertNil(prs[0].reviewDecision)
        XCTAssertFalse(prs[0].isConflicting)
    }

    func testEnrichMarksSuccessWhenAllChecksGood() {
        let base = makePR(json: #"""
        [{"number":1,"title":"t","url":"https://x","isDraft":false,"repository":{"nameWithOwner":"o/r"},"createdAt":"2026-06-01T12:00:00Z"}]
        """#)
        let detail = #"{"statusCheckRollup":[{"conclusion":"SUCCESS","state":null},{"conclusion":"NEUTRAL","state":null}],"reviewDecision":"APPROVED","mergeable":"MERGEABLE"}"#

        let enriched = enrichPullRequest(base, withDetailJSON: detail.data(using: .utf8)!)

        XCTAssertEqual(enriched.ciStatus, "SUCCESS")
        XCTAssertEqual(enriched.reviewDecision, "APPROVED")
        XCTAssertFalse(enriched.isConflicting)
    }

    func testEnrichMarksFailureWhenAnyCheckFails() {
        let base = makePR(json: #"""
        [{"number":2,"title":"t","url":"https://x","isDraft":true,"repository":{"nameWithOwner":"o/r"},"createdAt":"2026-06-01T12:00:00Z"}]
        """#)
        let detail = #"{"statusCheckRollup":[{"conclusion":"SUCCESS","state":null},{"conclusion":"FAILURE","state":null}],"reviewDecision":"CHANGES_REQUESTED","mergeable":"CONFLICTING"}"#

        let enriched = enrichPullRequest(base, withDetailJSON: detail.data(using: .utf8)!)

        XCTAssertEqual(enriched.ciStatus, "FAILURE")
        XCTAssertEqual(enriched.reviewDecision, "CHANGES_REQUESTED")
        XCTAssertTrue(enriched.isConflicting)
    }

    func testEnrichDefaultsToPendingWithNoChecks() {
        let base = makePR(json: #"""
        [{"number":3,"title":"t","url":"https://x","isDraft":false,"repository":{"nameWithOwner":"o/r"},"createdAt":"2026-06-01T12:00:00Z"}]
        """#)
        let detail = #"{"statusCheckRollup":[],"reviewDecision":null,"mergeable":"MERGEABLE"}"#

        let enriched = enrichPullRequest(base, withDetailJSON: detail.data(using: .utf8)!)

        XCTAssertEqual(enriched.ciStatus, "PENDING")
        XCTAssertNil(enriched.reviewDecision)
    }

    func testAgeDaysComputedFromCreatedAt() {
        let base = makePR(json: #"""
        [{"number":4,"title":"t","url":"https://x","isDraft":false,"repository":{"nameWithOwner":"o/r"},"createdAt":"2020-01-01T00:00:00Z"}]
        """#)
        XCTAssertGreaterThan(base.ageDays, 365)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PullRequestInfoTests`
Expected: FAIL — `cannot find 'parseSearchResults' in scope`.

- [ ] **Step 3: Implement `PullRequestInfo.swift`**

```swift
import Foundation

struct PullRequestInfo: Identifiable, Sendable {
    let id: Int
    let number: Int
    let title: String
    let url: String
    let repo: String
    let isDraft: Bool
    let createdAt: Date
    var ciStatus: String = "PENDING"
    var reviewDecision: String?
    var isConflicting: Bool = false

    var ageDays: Int {
        max(0, Int(Date().timeIntervalSince(createdAt) / 86400))
    }
}

private struct SearchRepository: Decodable {
    let nameWithOwner: String
}

private struct SearchResultItem: Decodable {
    let number: Int
    let title: String
    let url: String
    let isDraft: Bool
    let repository: SearchRepository
    let createdAt: String
}

private let ghDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

func parseSearchResults(_ data: Data) -> [PullRequestInfo] {
    guard let items = try? JSONDecoder().decode([SearchResultItem].self, from: data) else { return [] }

    return items.compactMap { item in
        guard let created = ghDateFormatter.date(from: item.createdAt) else { return nil }
        return PullRequestInfo(
            id: item.number,
            number: item.number,
            title: item.title,
            url: item.url,
            repo: item.repository.nameWithOwner,
            isDraft: item.isDraft,
            createdAt: created
        )
    }
}

private struct CheckRun: Decodable {
    let conclusion: String?
    let state: String?
}

private struct DetailResult: Decodable {
    let statusCheckRollup: [CheckRun]?
    let reviewDecision: String?
    let mergeable: String?
}

func enrichPullRequest(_ pr: PullRequestInfo, withDetailJSON data: Data) -> PullRequestInfo {
    guard let detail = try? JSONDecoder().decode(DetailResult.self, from: data) else { return pr }

    var updated = pr
    let states = (detail.statusCheckRollup ?? []).map { $0.conclusion ?? $0.state ?? "PENDING" }

    let failureStates: Set<String> = ["FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE"]
    let successStates: Set<String> = ["SUCCESS", "NEUTRAL", "SKIPPED", "EXPECTED"]

    if states.isEmpty {
        updated.ciStatus = "PENDING"
    } else if states.contains(where: { failureStates.contains($0) }) {
        updated.ciStatus = "FAILURE"
    } else if states.allSatisfy({ successStates.contains($0) }) {
        updated.ciStatus = "SUCCESS"
    } else {
        updated.ciStatus = "PENDING"
    }

    updated.reviewDecision = (detail.reviewDecision?.isEmpty == false) ? detail.reviewDecision : nil
    updated.isConflicting = detail.mergeable == "CONFLICTING"
    return updated
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PullRequestInfoTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalDashboard/Models/PullRequestInfo.swift Tests/LocalDashboardTests/PullRequestInfoTests.swift
git commit -m "Add PullRequestInfo: parse gh search results and per-PR CI/review enrichment"
```

---

### Task 8: ProcessRunner + KeychainTokenProvider

**Files:**
- Create: `Sources/LocalDashboard/Services/ProcessRunner.swift`
- Create: `Sources/LocalDashboard/Services/KeychainTokenProvider.swift`
- Test: `Tests/LocalDashboardTests/ProcessRunnerTests.swift`

**Interfaces:**
- Produces: `protocol ProcessRunning: Sendable { func run(_ path: String, _ args: [String]) -> String? }`, `struct SystemProcessRunner: ProcessRunning`, `protocol KeychainTokenProviding: Sendable { func fetchOAuthToken() -> String? }`, `struct KeychainTokenProvider: KeychainTokenProviding { init(runner: ProcessRunning = SystemProcessRunner()) }`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import LocalDashboard

final class ProcessRunnerTests: XCTestCase {
    func testSystemProcessRunnerExecutesRealCommand() {
        let runner = SystemProcessRunner()
        let output = runner.run("/bin/echo", ["hello"])
        XCTAssertEqual(output?.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    func testSystemProcessRunnerReturnsNilOnNonZeroExit() {
        let runner = SystemProcessRunner()
        XCTAssertNil(runner.run("/usr/bin/false", []))
    }
}

private struct FakeProcessRunner: ProcessRunning {
    let output: String?
    func run(_ path: String, _ args: [String]) -> String? { output }
}

final class KeychainTokenProviderTests: XCTestCase {
    func testExtractsTokenFromValidJSON() {
        let fake = FakeProcessRunner(output: #"{"claudeAiOauth":{"accessToken":"abc123"}}"#)
        let provider = KeychainTokenProvider(runner: fake)
        XCTAssertEqual(provider.fetchOAuthToken(), "abc123")
    }

    func testReturnsNilWhenRunnerFails() {
        let provider = KeychainTokenProvider(runner: FakeProcessRunner(output: nil))
        XCTAssertNil(provider.fetchOAuthToken())
    }

    func testReturnsNilOnMalformedJSON() {
        let provider = KeychainTokenProvider(runner: FakeProcessRunner(output: "not json"))
        XCTAssertNil(provider.fetchOAuthToken())
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ProcessRunnerTests`
Expected: FAIL — `cannot find type 'ProcessRunning' in scope`.

- [ ] **Step 3: Implement `ProcessRunner.swift`**

```swift
import Foundation

protocol ProcessRunning: Sendable {
    func run(_ path: String, _ args: [String]) -> String?
}

struct SystemProcessRunner: ProcessRunning {
    func run(_ path: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
```

- [ ] **Step 4: Implement `KeychainTokenProvider.swift`**

```swift
import Foundation

protocol KeychainTokenProviding: Sendable {
    func fetchOAuthToken() -> String?
}

struct KeychainTokenProvider: KeychainTokenProviding {
    let runner: ProcessRunning

    init(runner: ProcessRunning = SystemProcessRunner()) {
        self.runner = runner
    }

    func fetchOAuthToken() -> String? {
        guard let output = runner.run(
            "/usr/bin/security",
            ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        ) else { return nil }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return nil }

        return token
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter "ProcessRunnerTests|KeychainTokenProviderTests"`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/LocalDashboard/Services/ProcessRunner.swift Sources/LocalDashboard/Services/KeychainTokenProvider.swift Tests/LocalDashboardTests/ProcessRunnerTests.swift
git commit -m "Add ProcessRunner and KeychainTokenProvider services"
```

---

### Task 9: PullRequestFetcher

**Files:**
- Create: `Sources/LocalDashboard/Services/PullRequestFetcher.swift`
- Test: `Tests/LocalDashboardTests/PullRequestFetcherTests.swift`

**Interfaces:**
- Consumes: `ProcessRunning` (Task 8); `parseSearchResults(_:)`, `enrichPullRequest(_:withDetailJSON:)`, `PullRequestInfo` (Task 7).
- Produces: `func fetchPullRequests(runner: ProcessRunning) -> [PullRequestInfo]?`.

Uses `/usr/bin/env gh ...` (not a hardcoded Homebrew path) so it works regardless of where `gh` is installed (Apple Silicon `/opt/homebrew`, Intel `/usr/local`, or a manual install).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import LocalDashboard

private struct FakeGHRunner: ProcessRunning {
    let searchOutput: String?
    let detailOutputs: [String: String]

    func run(_ path: String, _ args: [String]) -> String? {
        if args.contains("search") { return searchOutput }
        if args.contains("view"), let number = args.first(where: { Int($0) != nil }) {
            return detailOutputs[number]
        }
        return nil
    }
}

final class PullRequestFetcherTests: XCTestCase {
    func testFetchPullRequestsEnrichesEachResult() {
        let search = """
        [{"number":10,"title":"Fix bug","url":"https://x/10","isDraft":false,"repository":{"nameWithOwner":"o/r"},"createdAt":"2026-06-01T12:00:00Z"}]
        """
        let detail = #"{"statusCheckRollup":[{"conclusion":"SUCCESS","state":null}],"reviewDecision":"APPROVED","mergeable":"MERGEABLE"}"#
        let runner = FakeGHRunner(searchOutput: search, detailOutputs: ["10": detail])

        let result = fetchPullRequests(runner: runner)

        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?[0].ciStatus, "SUCCESS")
        XCTAssertEqual(result?[0].reviewDecision, "APPROVED")
    }

    func testReturnsNilWhenSearchFails() {
        let runner = FakeGHRunner(searchOutput: nil, detailOutputs: [:])
        XCTAssertNil(fetchPullRequests(runner: runner))
    }

    func testKeepsUnenrichedRowWhenDetailCallFails() {
        let search = """
        [{"number":11,"title":"No detail","url":"https://x/11","isDraft":false,"repository":{"nameWithOwner":"o/r"},"createdAt":"2026-06-01T12:00:00Z"}]
        """
        let runner = FakeGHRunner(searchOutput: search, detailOutputs: [:])

        let result = fetchPullRequests(runner: runner)

        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?[0].ciStatus, "PENDING")
    }

    func testEmptySearchResultsReturnsEmptyArray() {
        let runner = FakeGHRunner(searchOutput: "[]", detailOutputs: [:])
        XCTAssertEqual(fetchPullRequests(runner: runner)?.count, 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PullRequestFetcherTests`
Expected: FAIL — `cannot find 'fetchPullRequests' in scope`.

- [ ] **Step 3: Implement `PullRequestFetcher.swift`**

```swift
import Foundation

func fetchPullRequests(runner: ProcessRunning) -> [PullRequestInfo]? {
    guard let searchOutput = runner.run("/usr/bin/env", [
        "gh", "search", "prs", "--author=@me", "--state=open",
        "--json", "number,title,url,isDraft,repository,createdAt"
    ]), let searchData = searchOutput.data(using: .utf8) else { return nil }

    let prs = parseSearchResults(searchData)

    var enriched: [PullRequestInfo] = []
    for pr in prs {
        guard let detailOutput = runner.run("/usr/bin/env", [
            "gh", "pr", "view", "\(pr.number)", "--repo", pr.repo,
            "--json", "statusCheckRollup,reviewDecision,mergeable"
        ]), let detailData = detailOutput.data(using: .utf8) else {
            enriched.append(pr)
            continue
        }
        enriched.append(enrichPullRequest(pr, withDetailJSON: detailData))
    }
    return enriched
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PullRequestFetcherTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalDashboard/Services/PullRequestFetcher.swift Tests/LocalDashboardTests/PullRequestFetcherTests.swift
git commit -m "Add PullRequestFetcher: two-step gh search + per-PR enrichment"
```

---

### Task 10: UsageWindowFetcher

**Files:**
- Create: `Sources/LocalDashboard/Services/UsageWindowFetcher.swift`
- Test: `Tests/LocalDashboardTests/UsageWindowFetcherTests.swift`

**Interfaces:**
- Consumes: `KeychainTokenProviding` (Task 8); `parseUsageWindowResponse(_:)`, `UsageWindowInfo` (Task 6).
- Produces: `typealias DataTaskFunc = @Sendable (URLRequest) async throws -> (Data, URLResponse)`, `func fetchUsageWindow(tokenProvider: KeychainTokenProviding, dataTask: DataTaskFunc) async -> UsageWindowInfo?`.

`DataTaskFunc` matches `URLSession.shared.data(for:)`'s signature exactly, so production code passes that method reference directly; tests inject a stub closure instead of standing up a real `URLProtocol` mock.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import LocalDashboard

private struct FakeTokenProvider: KeychainTokenProviding {
    let token: String?
    func fetchOAuthToken() -> String? { token }
}

final class UsageWindowFetcherTests: XCTestCase {
    func testReturnsNilWhenNoToken() async {
        let dataTask: DataTaskFunc = { _ in (Data(), URLResponse()) }
        let result = await fetchUsageWindow(tokenProvider: FakeTokenProvider(token: nil), dataTask: dataTask)
        XCTAssertNil(result)
    }

    func testParsesSuccessfulResponse() async {
        let json = #"{"extra_usage":{"used_credits":1000,"monthly_limit":5000,"utilization":20.0}}"#
        let dataTask: DataTaskFunc = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (json.data(using: .utf8)!, response)
        }
        let result = await fetchUsageWindow(tokenProvider: FakeTokenProvider(token: "tok"), dataTask: dataTask)
        XCTAssertEqual(result?.usedPercent, 20)
    }

    func testReturnsNilOnNon200Status() async {
        let dataTask: DataTaskFunc = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }
        let result = await fetchUsageWindow(tokenProvider: FakeTokenProvider(token: "tok"), dataTask: dataTask)
        XCTAssertNil(result)
    }

    func testReturnsNilWhenDataTaskThrows() async {
        struct FetchError: Error {}
        let dataTask: DataTaskFunc = { _ in throw FetchError() }
        let result = await fetchUsageWindow(tokenProvider: FakeTokenProvider(token: "tok"), dataTask: dataTask)
        XCTAssertNil(result)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter UsageWindowFetcherTests`
Expected: FAIL — `cannot find 'fetchUsageWindow' in scope`.

- [ ] **Step 3: Implement `UsageWindowFetcher.swift`**

```swift
import Foundation

typealias DataTaskFunc = @Sendable (URLRequest) async throws -> (Data, URLResponse)

func fetchUsageWindow(
    tokenProvider: KeychainTokenProviding,
    dataTask: DataTaskFunc
) async -> UsageWindowInfo? {
    guard let token = tokenProvider.fetchOAuthToken() else { return nil }
    guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return nil }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 3
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

    do {
        let (data, response) = try await dataTask(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return parseUsageWindowResponse(data)
    } catch {
        return nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter UsageWindowFetcherTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalDashboard/Services/UsageWindowFetcher.swift Tests/LocalDashboardTests/UsageWindowFetcherTests.swift
git commit -m "Add UsageWindowFetcher: call Anthropic usage API with injectable transport"
```

---

### Task 11: DashboardStore

**Files:**
- Create: `Sources/LocalDashboard/Services/DashboardStore.swift`
- Test: `Tests/LocalDashboardTests/DashboardStoreTests.swift`

**Interfaces:**
- Consumes: `computeSessionRows(sessionsDir:projectsDir:isAlive:)` (Task 5); `fetchUsageWindow(tokenProvider:dataTask:)`, `DataTaskFunc` (Task 10); `fetchPullRequests(runner:)` (Task 9); `KeychainTokenProviding`, `KeychainTokenProvider`, `ProcessRunning`, `SystemProcessRunner` (Task 8); `SessionRow` (Task 5); `UsageWindowInfo` (Task 6); `PullRequestInfo` (Task 7).
- Produces: `@MainActor final class DashboardStore: ObservableObject` with `@Published var sessionRows: [SessionRow]`, `@Published var usage: UsageWindowInfo?`, `@Published var usageUnavailable: Bool`, `@Published var pullRequests: [PullRequestInfo]`, `@Published var prsUnavailable: Bool`, `var badgeCount: Int`, `func refreshSessions()`, `func refreshUsage() async`, `func refreshPullRequests() async`, `func refreshAll()`, `func startPolling()`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import LocalDashboard

private struct FakeTokenProvider: KeychainTokenProviding {
    let token: String?
    func fetchOAuthToken() -> String? { token }
}

private struct FakeRunner: ProcessRunning {
    let searchOutput: String?
    func run(_ path: String, _ args: [String]) -> String? {
        args.contains("search") ? searchOutput : nil
    }
}

final class DashboardStoreTests: XCTestCase {
    @MainActor
    func testRefreshSessionsPopulatesRowsForLiveSession() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sessionsDir = root.appendingPathComponent("sessions")
        let projectsDir = root.appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let currentPid = Int(ProcessInfo.processInfo.processIdentifier)
        let cwd = "/tmp/proj"
        let sessionId = "abc"
        try #"{"pid":\#(currentPid),"sessionId":"abc","cwd":"\#(cwd)","name":"proj","status":"busy"}"#
            .write(to: sessionsDir.appendingPathComponent("abc.json"), atomically: true, encoding: .utf8)

        let projDir = projectsDir.appendingPathComponent(encodedProjectDir(forCwd: cwd))
        try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
        try #"{"type":"assistant","message":{"model":"claude-sonnet-5","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":1,"output_tokens":1}}}"#
            .write(to: projDir.appendingPathComponent("\(sessionId).jsonl"), atomically: true, encoding: .utf8)

        let store = DashboardStore(sessionsDir: sessionsDir.path, projectsDir: projectsDir.path)
        store.refreshSessions()

        XCTAssertEqual(store.sessionRows.count, 1)
        XCTAssertEqual(store.sessionRows.first?.name, "proj")
    }

    @MainActor
    func testRefreshUsageSetsUsageOnSuccess() async {
        let json = #"{"extra_usage":{"used_credits":500,"monthly_limit":2000,"utilization":25.0}}"#
        let dataTask: DataTaskFunc = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (json.data(using: .utf8)!, response)
        }
        let store = DashboardStore(tokenProvider: FakeTokenProvider(token: "tok"), dataTask: dataTask)

        await store.refreshUsage()

        XCTAssertEqual(store.usage?.usedPercent, 25)
        XCTAssertFalse(store.usageUnavailable)
    }

    @MainActor
    func testRefreshUsageMarksUnavailableOnFailure() async {
        let dataTask: DataTaskFunc = { _ in (Data(), URLResponse()) }
        let store = DashboardStore(tokenProvider: FakeTokenProvider(token: nil), dataTask: dataTask)

        await store.refreshUsage()

        XCTAssertTrue(store.usageUnavailable)
    }

    @MainActor
    func testRefreshPullRequestsSetsBadgeCount() async {
        let search = """
        [{"number":1,"title":"a","url":"https://x/1","isDraft":false,"repository":{"nameWithOwner":"o/r"},"createdAt":"2026-06-01T12:00:00Z"},
         {"number":2,"title":"b","url":"https://x/2","isDraft":false,"repository":{"nameWithOwner":"o/r"},"createdAt":"2026-06-01T12:00:00Z"}]
        """
        let store = DashboardStore(processRunner: FakeRunner(searchOutput: search))

        await store.refreshPullRequests()

        XCTAssertEqual(store.pullRequests.count, 2)
        XCTAssertEqual(store.badgeCount, 2)
        XCTAssertFalse(store.prsUnavailable)
    }

    @MainActor
    func testRefreshPullRequestsMarksUnavailableOnFailure() async {
        let store = DashboardStore(processRunner: FakeRunner(searchOutput: nil))

        await store.refreshPullRequests()

        XCTAssertTrue(store.prsUnavailable)
        XCTAssertEqual(store.badgeCount, 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DashboardStoreTests`
Expected: FAIL — `cannot find 'DashboardStore' in scope`.

- [ ] **Step 3: Implement `DashboardStore.swift`**

```swift
import Foundation

@MainActor
final class DashboardStore: ObservableObject {
    @Published var sessionRows: [SessionRow] = []
    @Published var usage: UsageWindowInfo?
    @Published var usageUnavailable = false
    @Published var pullRequests: [PullRequestInfo] = []
    @Published var prsUnavailable = false

    private let sessionsDir: String
    private let projectsDir: String
    private let tokenProvider: KeychainTokenProviding
    private let processRunner: ProcessRunning
    private let dataTask: DataTaskFunc

    private var sessionTimer: Timer?
    private var apiTimer: Timer?

    var badgeCount: Int { pullRequests.count }

    init(
        sessionsDir: String = NSString(string: "~/.claude/sessions").expandingTildeInPath,
        projectsDir: String = NSString(string: "~/.claude/projects").expandingTildeInPath,
        tokenProvider: KeychainTokenProviding = KeychainTokenProvider(),
        processRunner: ProcessRunning = SystemProcessRunner(),
        dataTask: @escaping DataTaskFunc = URLSession.shared.data(for:)
    ) {
        self.sessionsDir = sessionsDir
        self.projectsDir = projectsDir
        self.tokenProvider = tokenProvider
        self.processRunner = processRunner
        self.dataTask = dataTask
    }

    func refreshSessions() {
        sessionRows = computeSessionRows(sessionsDir: sessionsDir, projectsDir: projectsDir)
    }

    func refreshUsage() async {
        if let result = await fetchUsageWindow(tokenProvider: tokenProvider, dataTask: dataTask) {
            usage = result
            usageUnavailable = false
        } else {
            usageUnavailable = true
        }
    }

    func refreshPullRequests() async {
        let runner = processRunner
        let result = await Task.detached(priority: .utility) { () -> [PullRequestInfo]? in
            fetchPullRequests(runner: runner)
        }.value

        if let result {
            pullRequests = result
            prsUnavailable = false
        } else {
            prsUnavailable = true
        }
    }

    func refreshAll() {
        refreshSessions()
        Task { await refreshUsage() }
        Task { await refreshPullRequests() }
    }

    func startPolling() {
        refreshAll()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshSessions() }
        }
        apiTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshUsage()
                await self?.refreshPullRequests()
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DashboardStoreTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalDashboard/Services/DashboardStore.swift Tests/LocalDashboardTests/DashboardStoreTests.swift
git commit -m "Add DashboardStore: aggregate sessions/usage/PRs with per-section failure isolation"
```

---

### Task 12: Section Views

**Files:**
- Create: `Sources/LocalDashboard/Views/UsageSectionView.swift`
- Create: `Sources/LocalDashboard/Views/SessionsSectionView.swift`
- Create: `Sources/LocalDashboard/Views/PullRequestsSectionView.swift`

**Interfaces:**
- Consumes: `UsageWindowInfo` (Task 6), `SessionRow` (Task 5), `PullRequestInfo` (Task 7).
- Produces: `UsageSectionView(usage: UsageWindowInfo?, unavailable: Bool)`, `SessionsSectionView(rows: [SessionRow])`, `PullRequestsSectionView(pullRequests: [PullRequestInfo], unavailable: Bool)`.

SwiftUI views aren't unit-testable without extra snapshot-testing infrastructure (out of scope for v1); the test cycle here is "builds cleanly" plus a manual visual check.

- [ ] **Step 1: Implement `UsageSectionView.swift`** ("big number block" layout)

```swift
import SwiftUI

struct UsageSectionView: View {
    let usage: UsageWindowInfo?
    let unavailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Usage").font(.headline)

            if unavailable {
                Text("Unavailable").foregroundStyle(.secondary)
            } else if let usage {
                Text("\(usage.usedPercent)%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(color(for: usage.usedPercent))
                ProgressView(value: Double(usage.usedPercent), total: 100)
                    .tint(color(for: usage.usedPercent))
                Text(String(format: "$%.2f / $%.0f", usage.usedUSD, usage.limitUSD))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Loading…").foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func color(for percent: Int) -> Color {
        if percent > 80 { return .red }
        if percent > 50 { return .yellow }
        return .green
    }
}
```

- [ ] **Step 2: Implement `SessionsSectionView.swift`** ("aligned columns" layout)

```swift
import SwiftUI

struct SessionsSectionView: View {
    let rows: [SessionRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sessions").font(.headline)

            if rows.isEmpty {
                Text("No active sessions").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                    ForEach(rows) { row in
                        GridRow {
                            Circle()
                                .fill(row.status == "busy" ? Color.yellow : Color.green)
                                .frame(width: 8, height: 8)
                            Text(row.name).lineLimit(1)
                            ProgressView(value: Double(row.contextPercent), total: 100)
                                .frame(width: 60)
                            Text("\(row.contextPercent)%")
                                .font(.caption)
                                .monospacedDigit()
                            Text(String(format: "$%.2f", row.costUSD))
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
```

- [ ] **Step 3: Implement `PullRequestsSectionView.swift`** ("statusline-style" layout — one line per PR, mirroring the original bash statusline's single-line PR format: truncated title, inline tags, CI dot, age pinned to the far right)

```swift
import SwiftUI

struct PullRequestsSectionView: View {
    let pullRequests: [PullRequestInfo]
    let unavailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pull Requests").font(.headline)

            if unavailable {
                Text("Unavailable").foregroundStyle(.secondary)
            } else if pullRequests.isEmpty {
                Text("No open PRs").foregroundStyle(.secondary)
            } else {
                ForEach(pullRequests) { pr in
                    HStack(spacing: 6) {
                        Text("#\(pr.number) \(pr.title)")
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if pr.isDraft {
                            tag("draft", .secondary)
                        }
                        if pr.reviewDecision == "APPROVED" {
                            tag("approved", .green)
                        } else if pr.reviewDecision == "CHANGES_REQUESTED" {
                            tag("changes", .red)
                        }
                        if pr.isConflicting {
                            tag("conflicts", .red)
                        }
                        ciDot(pr.ciStatus)
                        Spacer(minLength: 8)
                        Text(ageLabel(pr.ageDays))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func ciDot(_ status: String) -> some View {
        let color: Color = status == "SUCCESS" ? .green : (status == "FAILURE" ? .red : .yellow)
        return Circle().fill(color).frame(width: 8, height: 8)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func ageLabel(_ days: Int) -> String {
        if days >= 7 { return "\(days / 7)w" }
        if days >= 1 { return "\(days)d" }
        return "<1d"
    }
}
```

- [ ] **Step 4: Verify it builds**

Run: `swift build`
Expected: `Build complete!` with no errors (these views aren't wired into the app yet, so no visual check is possible until Task 13).

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalDashboard/Views/UsageSectionView.swift Sources/LocalDashboard/Views/SessionsSectionView.swift Sources/LocalDashboard/Views/PullRequestsSectionView.swift
git commit -m "Add Usage/Sessions/PullRequests section views"
```

---

### Task 13: Panel Assembly + Badge Icon

**Files:**
- Create: `Sources/LocalDashboard/Views/DashboardPanelView.swift`
- Modify: `Sources/LocalDashboard/LocalDashboardApp.swift` (replace Task 1's placeholder body)

**Interfaces:**
- Consumes: `DashboardStore` (Task 11), `UsageSectionView`, `SessionsSectionView`, `PullRequestsSectionView` (Task 12).
- Produces: `DashboardPanelView(store: DashboardStore)`, `func renderBadgeIcon(count: Int) -> NSImage`.

The badge icon uses a `CGContext(data: nil, ...)`-backed bitmap (not `NSImage.lockFocus`, which was verified in a scratch prototype to silently fail to draw when run outside a full windowed app context) with `.clear` blend mode to cut the number out of a solid white rounded rect.

- [ ] **Step 1: Implement `DashboardPanelView.swift`**

```swift
import SwiftUI

struct DashboardPanelView: View {
    @ObservedObject var store: DashboardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            UsageSectionView(usage: store.usage, unavailable: store.usageUnavailable)
            Divider()
            SessionsSectionView(rows: store.sessionRows)
            Divider()
            PullRequestsSectionView(pullRequests: store.pullRequests, unavailable: store.prsUnavailable)
            Divider()
            Button("Refresh") {
                store.refreshAll()
            }
            .padding(8)
        }
        .frame(width: 320)
    }
}
```

- [ ] **Step 2: Replace `LocalDashboardApp.swift`**

```swift
import SwiftUI
import AppKit

@main
struct LocalDashboardApp: App {
    @StateObject private var store = DashboardStore()

    var body: some Scene {
        MenuBarExtra {
            DashboardPanelView(store: store)
                .onAppear { store.startPolling() }
        } label: {
            if store.badgeCount > 0 {
                Image(nsImage: renderBadgeIcon(count: store.badgeCount))
            } else {
                Image(systemName: "gauge.medium")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

func renderBadgeIcon(count: Int) -> NSImage {
    let size = 18
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return NSImage(size: CGSize(width: size, height: size))
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let path = CGPath(roundedRect: rect, cornerWidth: 5, cornerHeight: 5, transform: nil)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addPath(path)
    ctx.fillPath()

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

    let text = "\(count)" as NSString
    let font = NSFont.systemFont(ofSize: 11, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    let textSize = text.size(withAttributes: attrs)
    let textRect = CGRect(
        x: (CGFloat(size) - textSize.width) / 2,
        y: (CGFloat(size) - textSize.height) / 2,
        width: textSize.width,
        height: textSize.height
    )
    ctx.setBlendMode(.clear)
    text.draw(in: textRect, withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()

    guard let cgImage = ctx.makeImage() else {
        return NSImage(size: CGSize(width: size, height: size))
    }
    let image = NSImage(cgImage: cgImage, size: CGSize(width: size, height: size))
    image.isTemplate = false
    return image
}
```

- [ ] **Step 3: Build and manually verify end-to-end**

Run: `swift build`
Expected: `Build complete!` with no errors.

Run: `swift run`
Expected: A gauge icon (or, if you have open PRs, a white badge with the PR count cut out) appears in the menu bar. Clicking it shows the panel with Usage, Sessions, and Pull Requests sections in that order, populated with real data from your machine within a few seconds. Click Refresh to confirm the manual refresh path works. Stop with Ctrl-C.

- [ ] **Step 4: Commit**

```bash
git add Sources/LocalDashboard/Views/DashboardPanelView.swift Sources/LocalDashboard/LocalDashboardApp.swift
git commit -m "Wire DashboardStore into MenuBarExtra panel with PR-count badge icon"
```

---

### Task 14: Final Polish

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Run the full test suite**

Run: `swift test`
Expected: All tests pass (36 tests across Tasks 2–11).

- [ ] **Step 2: Run a full build**

Run: `swift build -c release`
Expected: `Build complete!` with no errors or warnings.

- [ ] **Step 3: Update `README.md` with a short feature list**

```markdown
# LocalDashboard

A macOS menubar app showing Claude Code usage %, active sessions
(context window %, running cost), and your open GitHub pull requests —
independent of any terminal statusline, so it works the same whether
Claude Code runs in a terminal or the desktop app.

## Features

- **Usage** — Anthropic usage-window percentage, $ used / $ limit.
- **Sessions** — every live Claude Code session (desktop + terminal),
  with context-window % and running cost per session.
- **Pull Requests** — your open PRs across all repos, with CI status,
  draft/review/conflict tags, and age. The menu bar badge shows the
  open PR count.

Each section degrades independently to an "Unavailable" state if its
data source fails — one broken source never blocks the rest of the panel.

## Build & run

    swift build
    swift run

## Test

    swift test

## Requirements

- macOS 13+
- `gh` CLI, authenticated (`gh auth login`), for the pull requests section
- Claude Code Keychain credentials present (`Claude Code-credentials`), for the usage section
```

- [ ] **Step 4: Commit, tag, and push**

```bash
git add README.md
git commit -m "Update README with feature list"
git tag v0.1.0
git push origin main --tags
```

Expected: `main` and the `v0.1.0` tag are pushed to `https://github.com/mordechaih/localdashboard`.

---

## Self-Review

**Spec coverage:**
- Sessions data source (registry + transcript, pid liveness, context %, cost, skip-on-missing-transcript) → Tasks 2–5, 11.
- Usage window data source (OAuth Keychain token, `extra_usage`/`five_hour`/`seven_day` fallback, unavailable-on-failure) → Tasks 6, 8, 10, 11.
- Pull requests data source (all-repo two-step `gh` fetch, CI/review/conflict/age, unavailable-on-failure) → Tasks 7, 8, 9, 11.
- Badge icon (PR count, cutout style, omitted at 0) → Task 13.
- Panel layout and section order (Usage → Sessions → PRs; big-number-block / aligned-columns / statusline-style one-line) → Tasks 12, 13.
- Manual refresh control → Task 13 (`DashboardPanelView`'s Refresh button calling `store.refreshAll()`).
- Error handling (dead PIDs filtered silently, missing transcripts skip that session, failed APIs degrade only their section) → built into `loadSessions`/`computeSessionRows` (Tasks 4–5) and `usageUnavailable`/`prsUnavailable` (Task 11).
- Repo setup (public repo, MIT license, README, .gitignore) → Task 1, finalized in Task 14.
- Out-of-scope items (settings UI, launch-at-login, notifications, historical charts) — none of them appear anywhere in this plan, confirming they were correctly excluded.

**Placeholder scan:** No TBD/TODO markers; every step has complete, real code. The one deliberate deviation from the spec's literal wording (SwiftPM instead of `.xcodeproj`) is called out explicitly in Global Constraints rather than silently substituted.

**Type consistency:** Verified `SessionRow`, `UsageWindowInfo`, `PullRequestInfo`, `ProcessRunning`, `KeychainTokenProviding`, and `DataTaskFunc` are defined once (Tasks 2, 5, 6, 7, 8, 10) and referenced with identical names/signatures everywhere they're consumed downstream (Tasks 9, 11, 12, 13) — no drift between a type's defining task and its consumers.

---

**Plan complete and saved to `docs/superpowers/plans/2026-07-12-localdashboard-menubar.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
