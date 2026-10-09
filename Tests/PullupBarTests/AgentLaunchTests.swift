// Tests/PullupBarTests/AgentLaunchTests.swift
import XCTest
@testable import PullupBar

final class AgentLaunchTests: XCTestCase {
    func testDesktopSessionURLEncodesFolderAndOmitsPrompt() {
        XCTAssertEqual(
            claudeDesktopSessionURL(dir: "/clones/my repo"),
            "claude://code/new?folder=%2Fclones%2Fmy%20repo"
        )
    }

    func testDesktopSessionURLEncodesPromptReservedAndNonASCIICharacters() {
        // `&`, `=`, `+`, `?` and `'` must not leak into the query structure; `ü` is UTF-8 encoded.
        XCTAssertEqual(
            claudeDesktopSessionURL(dir: "/r", prompt: "a & b=c+d's ü?"),
            "claude://code/new?folder=%2Fr&q=a%20%26%20b%3Dc%2Bd%27s%20%C3%BC%3F"
        )
    }

    func testCursorPromptURLEncodesText() {
        XCTAssertEqual(
            cursorPromptURL(prompt: "a & b's ü?"),
            "cursor://anysphere.cursor-deeplink/prompt?text=a%20%26%20b%27s%20%C3%BC%3F"
        )
    }

    func testCLIInstalledFindsCommandInUserLocalBin() {
        XCTAssertTrue(isCLIInstalled(.cursor, home: "/Users/me", fileExists: { $0 == "/Users/me/.local/bin/agent" }))
    }

    func testCLIInstalledFindsCommandInHomebrewBin() {
        XCTAssertTrue(isCLIInstalled(.claude, home: "/Users/me", fileExists: { $0 == "/opt/homebrew/bin/claude" }))
    }

    func testCLIInstalledFalseWhenCommandIsNowhere() {
        XCTAssertFalse(isCLIInstalled(.cursor, home: "/Users/me", fileExists: { _ in false }))
    }
}
