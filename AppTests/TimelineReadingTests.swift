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

    func testSampleArrivingBetweenTimelineTicksUsesCurrentClock() {
        let tick = Date.now.addingTimeInterval(-1)
        let received = Date.now
        // TimelineView's context still holds `tick` when observation renders a
        // newly received sample. Reproduce the old 65 -> 61 / Live -> time switch.
        let scheduled = TimelineReading.resolve(value: 61, date: tick.addingTimeInterval(-60), wantsLive: true,
                                                sensorValue: 65, sensorDate: received, streaming: true, now: tick)
        XCTAssertEqual(scheduled.value, 61)
        XCTAssertFalse(scheduled.isLive)

        // The readout now uses this default clock on every render, including
        // observation updates that occur before the next scheduled tick.
        let current = TimelineReading.resolve(value: 61, date: tick.addingTimeInterval(-60), wantsLive: true,
                                              sensorValue: 65, sensorDate: received, streaming: true)
        XCTAssertEqual(current.value, 65)
        XCTAssertEqual(current.date, received)
        XCTAssertTrue(current.isLive)
    }

    func testInterleavedSensorUpdatesAndTicksNeverFallBackToOlderChart() {
        let samples: [(Double, UInt8)] = [(0.25, 65), (0.8, 66), (1.4, 64), (2.9, 65)]
        for seconds in [0.25, 0.8, 1, 1.4, 2, 2.9, 3, 7.9] {
            let sample = samples.last { $0.0 <= seconds }!
            let result = TimelineReading.resolve(value: 61, date: at.addingTimeInterval(-60), wantsLive: true,
                                                 sensorValue: sample.1, sensorDate: at.addingTimeInterval(sample.0),
                                                 streaming: true, now: at.addingTimeInterval(seconds))
            XCTAssertEqual(result.value, Double(sample.1))
            XCTAssertEqual(result.isLive, seconds - sample.0 < 5)
        }
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
