import AppKit

/// A terminal application the user can pick to open Claude Code sessions in.
struct TerminalApp: Sendable {
    let name: String
    let path: String
}

extension TerminalApp {
    /// Known terminal emulators, by bundle identifier. Terminal.app is intentionally omitted — it's
    /// the system default (represented by an empty `terminalAppPath`) and is offered separately.
    private static let knownBundleIDs: [(id: String, name: String)] = [
        ("com.googlecode.iterm2", "iTerm"),
        ("com.mitchellh.ghostty", "Ghostty"),
        ("com.github.wez.wezterm", "WezTerm"),
        ("dev.warp.Warp-Stable", "Warp"),
        ("net.kovidgoyal.kitty", "kitty"),
        ("org.alacritty", "Alacritty"),
        ("co.zeit.hyper", "Hyper"),
    ]

    /// The known terminals that are actually installed, resolved to their `.app` paths via
    /// `NSWorkspace`. Returned in the fixed order above.
    static func detectInstalled() -> [TerminalApp] {
        let workspace = NSWorkspace.shared
        return knownBundleIDs.compactMap { candidate in
            guard let url = workspace.urlForApplication(withBundleIdentifier: candidate.id) else { return nil }
            return TerminalApp(name: candidate.name, path: url.path)
        }
    }

    /// The Finder icon for the app at `path`, sized to `size` points. An empty `path` (the default
    /// selection) resolves to Terminal.app's icon.
    static func icon(forPath path: String, size: CGFloat = 16) -> NSImage {
        let resolved = path.isEmpty
            ? (NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")?.path ?? "")
            : path
        let icon = NSWorkspace.shared.icon(forFile: resolved)
        let sized = (icon.copy() as? NSImage) ?? icon
        sized.size = NSSize(width: size, height: size)
        return sized
    }

    /// An SF Symbol centered on a `size`-point square template image, so a symbol menu item's title
    /// lines up with the titles next to the 16pt app icons. Template, so it follows the menu's
    /// highlight and appearance.
    static func symbolIcon(_ name: String, size: CGFloat = 16) -> NSImage {
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let symbol else { return false }
            let s = symbol.size
            symbol.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height))
            return true
        }
        image.isTemplate = true
        return image
    }
}
