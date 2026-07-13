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
