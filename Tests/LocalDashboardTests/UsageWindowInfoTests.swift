import XCTest
@testable import LocalDashboard

final class UsageWindowInfoTests: XCTestCase {
    func testParsesExtraUsageBucket() {
        let json = #"{"extra_usage":{"used_credits":1234,"monthly_limit":10000,"utilization":45.7}}"#
        let info = parseUsageWindowResponse(json.data(using: .utf8)!)

        XCTAssertEqual(info?.usedUSD ?? -1, 12.34, accuracy: 0.001)
        XCTAssertEqual(info?.limitUSD ?? -1, 100.0, accuracy: 0.001)
        XCTAssertEqual(info?.usedPercent, 45)
    }

    func testFallsBackToFiveHourWhenExtraUsageMissing() {
        let json = #"{"five_hour":{"used_credits":500,"monthly_limit":2000,"utilization":25.0}}"#
        let info = parseUsageWindowResponse(json.data(using: .utf8)!)

        XCTAssertEqual(info?.usedUSD ?? -1, 5.0, accuracy: 0.001)
    }

    func testFallsBackToSevenDayWhenOthersMissing() {
        let json = #"{"seven_day":{"used_credits":700,"monthly_limit":3000,"utilization":10.9}}"#
        let info = parseUsageWindowResponse(json.data(using: .utf8)!)

        XCTAssertEqual(info?.usedPercent, 10) // floor, not round
    }

    func testReturnsNilWhenNoBucketsPresent() {
        XCTAssertNil(parseUsageWindowResponse("{}".data(using: .utf8)!))
    }

    func testReturnsNilOnMalformedJSON() {
        XCTAssertNil(parseUsageWindowResponse("not json".data(using: .utf8)!))
    }
}
