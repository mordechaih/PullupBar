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

    func testEnrichFallsBackToPendingForMixedNonFailureNonSuccessStates() {
        let base = makePR(json: #"""
        [{"number":5,"title":"t","url":"https://x","isDraft":false,"repository":{"nameWithOwner":"o/r"},"createdAt":"2026-06-01T12:00:00Z"}]
        """#)
        let detail = #"{"statusCheckRollup":[{"conclusion":"SUCCESS","state":null},{"conclusion":null,"state":"PENDING"}],"reviewDecision":null,"mergeable":"MERGEABLE"}"#

        let enriched = enrichPullRequest(base, withDetailJSON: detail.data(using: .utf8)!)

        XCTAssertEqual(enriched.ciStatus, "PENDING")
    }

    func testAgeDaysComputedFromCreatedAt() {
        let base = makePR(json: #"""
        [{"number":4,"title":"t","url":"https://x","isDraft":false,"repository":{"nameWithOwner":"o/r"},"createdAt":"2020-01-01T00:00:00Z"}]
        """#)
        XCTAssertGreaterThan(base.ageDays, 365)
    }

    func testEnrichParsesDiffStats() {
        let base = makePR(json: #"""
        [{"number":6,"title":"t","url":"https://x","isDraft":false,"repository":{"nameWithOwner":"o/r"},"createdAt":"2026-06-01T12:00:00Z"}]
        """#)
        let detail = #"{"statusCheckRollup":[],"reviewDecision":null,"mergeable":"MERGEABLE","additions":128,"deletions":20,"changedFiles":9}"#

        let enriched = enrichPullRequest(base, withDetailJSON: detail.data(using: .utf8)!)

        XCTAssertEqual(enriched.additions, 128)
        XCTAssertEqual(enriched.deletions, 20)
        XCTAssertEqual(enriched.changedFiles, 9)
    }

    private func makeTriagePR(
        isDraft: Bool = false,
        ciStatus: String = "PENDING",
        reviewDecision: String? = nil,
        isConflicting: Bool = false
    ) -> PullRequestInfo {
        PullRequestInfo(
            id: "o/r#1", number: 1, title: "t", url: "https://x", repo: "o/r",
            isDraft: isDraft, createdAt: Date(), ciStatus: ciStatus,
            reviewDecision: reviewDecision, isConflicting: isConflicting
        )
    }

    func testTriageLaneDraftAlwaysWinsRegardlessOfOtherState() {
        let pr = makeTriagePR(isDraft: true, ciStatus: "FAILURE", reviewDecision: "CHANGES_REQUESTED", isConflicting: true)
        XCTAssertEqual(triageLane(for: pr), .draft)
    }

    func testTriageLaneNeedsAttentionOnCIFailure() {
        let pr = makeTriagePR(ciStatus: "FAILURE")
        XCTAssertEqual(triageLane(for: pr), .needsAttention)
    }

    func testTriageLaneNeedsAttentionOnChangesRequested() {
        let pr = makeTriagePR(reviewDecision: "CHANGES_REQUESTED")
        XCTAssertEqual(triageLane(for: pr), .needsAttention)
    }

    func testTriageLaneNeedsAttentionOnConflict() {
        let pr = makeTriagePR(isConflicting: true)
        XCTAssertEqual(triageLane(for: pr), .needsAttention)
    }

    func testTriageLaneReadyToMergeWhenSuccessAndApproved() {
        let pr = makeTriagePR(ciStatus: "SUCCESS", reviewDecision: "APPROVED")
        XCTAssertEqual(triageLane(for: pr), .readyToMerge)
    }

    func testTriageLaneAwaitingReviewOtherwise() {
        let pr = makeTriagePR(ciStatus: "PENDING")
        XCTAssertEqual(triageLane(for: pr), .awaitingReview)
    }

    func testParseSearchResultsTagsMergeStateAndClosedAt() {
        let json = #"""
        [{"number":7,"title":"landed","url":"https://x/7","isDraft":false,"repository":{"nameWithOwner":"o/r"},"createdAt":"2026-06-01T12:00:00Z","closedAt":"2026-06-05T09:00:00Z"}]
        """#
        let prs = parseSearchResults(json.data(using: .utf8)!, isMerged: true)

        XCTAssertEqual(prs.count, 1)
        XCTAssertTrue(prs[0].isMerged)
        XCTAssertNotNil(prs[0].closedAt)
        XCTAssertNotNil(prs[0].closedAgeDays)
    }

    func testParseSearchResultsDefaultsToUnmergedWithNilClosedAt() {
        let json = #"""
        [{"number":8,"title":"open","url":"https://x/8","isDraft":false,"repository":{"nameWithOwner":"o/r"},"createdAt":"2026-06-01T12:00:00Z"}]
        """#
        let prs = parseSearchResults(json.data(using: .utf8)!)

        XCTAssertFalse(prs[0].isMerged)
        XCTAssertNil(prs[0].closedAt)
        XCTAssertNil(prs[0].closedAgeDays)
    }

    func testClosedGroupMapsMergeState() {
        var pr = makeTriagePR()
        pr.isMerged = true
        XCTAssertEqual(closedGroup(for: pr), .merged)
        pr.isMerged = false
        XCTAssertEqual(closedGroup(for: pr), .closed)
    }
}
