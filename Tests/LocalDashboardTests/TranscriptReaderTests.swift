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
