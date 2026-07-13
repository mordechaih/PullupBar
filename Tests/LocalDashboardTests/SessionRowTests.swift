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
