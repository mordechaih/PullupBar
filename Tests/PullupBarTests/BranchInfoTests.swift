// Tests/PullupBarTests/BranchInfoTests.swift
import XCTest
@testable import PullupBar

final class BranchInfoTests: XCTestCase {
    func testParseOriginURLHandlesSSH() {
        XCTAssertEqual(parseOriginURL("git@github.com:owner/repo.git"), "owner/repo")
    }

    func testParseOriginURLHandlesHTTPS() {
        XCTAssertEqual(parseOriginURL("https://github.com/owner/repo.git\n"), "owner/repo")
    }

    func testParseOriginURLHandlesNoGitSuffix() {
        XCTAssertEqual(parseOriginURL("https://github.com/owner/repo"), "owner/repo")
    }

    func testParseOriginURLReturnsNilForGarbage() {
        XCTAssertNil(parseOriginURL(""))
        XCTAssertNil(parseOriginURL("not-a-url"))
    }

    func testParseBranchRefsSplitsFields() {
        let output = "feature-x\t<me@x.com>\t1700000000\nfeature-y\t<you@x.com>\t1700000100\n"
        let refs = parseBranchRefs(output)
        XCTAssertEqual(refs.count, 2)
        XCTAssertEqual(refs[0].name, "feature-x")
        XCTAssertEqual(refs[0].authorEmail, "me@x.com")
        XCTAssertEqual(refs[0].tipDate, Date(timeIntervalSince1970: 1700000000))
    }

    func testParseBranchRefsSkipsBlankAndMalformedLines() {
        let output = "\ngood\t<a@b.com>\t123\nmalformed-no-tabs\n"
        let refs = parseBranchRefs(output)
        XCTAssertEqual(refs.map(\.name), ["good"])
    }
}
