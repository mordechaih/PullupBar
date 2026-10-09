import AppKit

/// A coding agent PullupBar can start sessions with (Create PR, and checkout when
/// `openAgentOnCheckout` is on).
enum CodingAgent: String, CaseIterable, Sendable {
    case claude
    case cursor

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .cursor: "Cursor"
        }
    }

    var desktopAppName: String {
        switch self {
        case .claude: "Claude desktop app"
        case .cursor: "Cursor app"
        }
    }

    var desktopAppBundleID: String {
        switch self {
        case .claude: "com.anthropic.claudefordesktop"
        case .cursor: "com.todesktop.230313mzl4w4u92"
        }
    }

    /// The CLI the terminal script runs.
    var cliCommand: String {
        switch self {
        case .claude: "claude"
        case .cursor: "agent"
        }
    }

    /// Shown when the CLI is missing. Nil where PullupBar doesn't check (Claude's CLI is already a
    /// prerequisite of the terminal flow).
    var cliInstallCommand: String? {
        switch self {
        case .claude: nil
        case .cursor: "curl https://cursor.com/install -fsS | bash"
        }
    }

    /// The installed desktop app's `.app` path, or nil if it isn't installed.
    func desktopAppPath() -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: desktopAppBundleID)?.path
    }
}

/// Where a session opens.
enum AgentDestination: Equatable, Sendable {
    /// A terminal running the agent's CLI. An empty `appPath` means the system default handler
    /// for `.command` scripts (Terminal).
    case terminal(appPath: String)
    /// The agent's own desktop app.
    case desktopApp
}

/// Whether `agent`'s CLI is in one of the directories its installers use. PullupBar's own PATH
/// (inherited from launchd) doesn't include them, so this checks the files directly.
func isCLIInstalled(
    _ agent: CodingAgent,
    home: String = NSHomeDirectory(),
    fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
) -> Bool {
    ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        .contains { fileExists("\($0)/\(agent.cliCommand)") }
}

/// RFC 3986 unreserved characters. Everything else is percent-encoded, so `&`, `=`, `+` and
/// non-ASCII text in a path or prompt can't change the query's structure.
private let unreservedQueryCharacters = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
)

private func queryEncode(_ s: String) -> String {
    s.addingPercentEncoding(withAllowedCharacters: unreservedQueryCharacters) ?? s
}

/// The Claude desktop app's deep link for a new Claude Code session with `dir` selected as the
/// folder and, when given, `prompt` filled in (never sent).
func claudeDesktopSessionURL(dir: String, prompt: String? = nil) -> String {
    var url = "claude://code/new?folder=\(queryEncode(dir))"
    if let prompt { url += "&q=\(queryEncode(prompt))" }
    return url
}

/// Cursor's deeplink that fills `prompt` into the chat of the frontmost Cursor window (never
/// sent). It has no folder parameter, so the folder has to be opened first.
func cursorPromptURL(prompt: String) -> String {
    "cursor://anysphere.cursor-deeplink/prompt?text=\(queryEncode(prompt))"
}

/// Gives a desktop app time to bring forward the folder window just opened, so a prompt link sent
/// next lands in it: waits (up to 15s) for the app to finish launching, then pauses, longer after
/// a cold start since the app also restores its other windows then.
func waitForDesktopApp(_ agent: CodingAgent) {
    let deadline = Date().addingTimeInterval(15)
    var coldStart = false
    while Date() < deadline,
          NSRunningApplication.runningApplications(withBundleIdentifier: agent.desktopAppBundleID)
              .first?.isFinishedLaunching != true {
        coldStart = true
        Thread.sleep(forTimeInterval: 0.25)
    }
    Thread.sleep(forTimeInterval: coldStart ? 3 : 1.5)
}
