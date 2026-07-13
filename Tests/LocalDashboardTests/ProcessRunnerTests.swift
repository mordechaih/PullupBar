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

    func testSystemProcessRunnerExecutesInGivenWorkingDirectory() {
        let runner = SystemProcessRunner()
        let output = runner.run("/bin/pwd", [], cwd: "/tmp")
        XCTAssertEqual(output?.trimmingCharacters(in: .whitespacesAndNewlines), "/private/tmp")
    }
}
