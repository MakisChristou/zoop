import XCTest
@testable import Zoop

final class ChartPresentationTests: XCTestCase {
    func testCurrentPeriodDoesNotReserveSpaceForFutureReadings() {
        let start = Date(timeIntervalSince1970: 100), end = start.addingTimeInterval(30 * 86400)
        let now = start.addingTimeInterval(10 * 86400)
        let domain = ChartPresentation.dateDomain(DateInterval(start: start, end: end), now: now)
        XCTAssertEqual(domain.lowerBound, start)
        XCTAssertEqual(domain.upperBound, now)
        XCTAssertEqual(ChartPresentation.dateTicks(domain).count, 3)
    }
    func testHistoricPeriodRetainsItsWholeCalendarWindowAndFutureRangeIsNonempty() {
        let start = Date(timeIntervalSince1970: 100), end = start.addingTimeInterval(86400)
        let interval = DateInterval(start: start, end: end)
        XCTAssertEqual(ChartPresentation.dateDomain(interval, now: end.addingTimeInterval(100)).upperBound, end.addingTimeInterval(-1))
        XCTAssertGreaterThan(ChartPresentation.dateDomain(interval, now: start.addingTimeInterval(-100)).upperBound, start)
    }
    func testThreeReadableTicksContainNegativeSmallAndFlatRanges() {
        for range in [51.0...77, 6.8...8.1, 33.2...33.6, -2.0...2, 70.0...70, 0.0...0, 1000.0...14000] {
            let ticks = ChartPresentation.ticks(range)
            XCTAssertEqual(ticks.count, 3)
            XCTAssertLessThanOrEqual(ticks[0], range.lowerBound)
            XCTAssertGreaterThanOrEqual(ticks[2] + 0.000001, range.upperBound)
            XCTAssertGreaterThan(ticks[1], ticks[0])
            XCTAssertEqual(ticks[2] - ticks[1], ticks[1] - ticks[0], accuracy: 0.000001)
        }
    }
}
