import XCTest
@testable import Zoop

final class TimelineReadingTests: XCTestCase {
    private let at = Date(timeIntervalSince1970: 1_795_000_000)
    private func reading(after seconds: Double, streaming: Bool = true, wantsLive: Bool = true) -> TimelineReading {
        .resolve(value: 61, date: at.addingTimeInterval(-60), wantsLive: wantsLive,
                 sensorValue: 65, sensorDate: at, streaming: streaming,
                 now: at.addingTimeInterval(seconds))
    }

    func testFreshnessExpiryDoesNotReplaceLiveReadingWithChartAverage() {
        XCTAssertEqual(reading(after: 4).value, 65)
        XCTAssertTrue(reading(after: 4).isLive)
        XCTAssertEqual(reading(after: 5).value, 65)
        XCTAssertEqual(reading(after: 30).date, at)
        XCTAssertFalse(reading(after: 5).isLive)
    }

    func testDisconnectKeepsTimestampedReadingWithoutLiveLabel() {
        XCTAssertEqual(reading(after: 1, streaming: false).value, 65)
        XCTAssertFalse(reading(after: 1, streaming: false).isLive)
    }

    func testNewerChartReadingCanReplaceStaleSensorValue() {
        let result = TimelineReading.resolve(value: 70, date: at.addingTimeInterval(60), wantsLive: true,
                                             sensorValue: 65, sensorDate: at, streaming: false,
                                             now: at.addingTimeInterval(90))
        XCTAssertEqual(result.value, 70)
        XCTAssertEqual(result.date, at.addingTimeInterval(60))
        XCTAssertFalse(result.isLive)
    }

    func testHistoricalSelectionAlwaysUsesSelectedChartReading() {
        XCTAssertEqual(reading(after: 1, wantsLive: false).value, 61)
        XCTAssertEqual(reading(after: 1, wantsLive: false).date, at.addingTimeInterval(-60))
    }

    func testMissingFutureAndPreviousDaySensorValuesUseChartReading() {
        XCTAssertEqual(reading(after: -1).value, 61)
        XCTAssertEqual(reading(after: 86_400).value, 61)
        let result = TimelineReading.resolve(value: nil, date: nil, wantsLive: true,
                                             sensorValue: nil, sensorDate: nil,
                                             streaming: true, now: at)
        XCTAssertNil(result.value)
        XCTAssertFalse(result.isLive)
    }
}
