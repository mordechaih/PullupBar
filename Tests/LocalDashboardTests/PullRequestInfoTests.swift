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
