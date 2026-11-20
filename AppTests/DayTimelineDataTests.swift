import XCTest
@testable import Zoop

final class DayTimelineDataTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 20))! }
    private func minute(_ offset: Double, hr: Int? = 60, temp: Double? = 33, band: Int? = nil, activity: Int? = nil) -> ZoopAPI.Minute {
        .init(ts: day.addingTimeInterval(offset), hr: hr, hrMin: nil, hrMax: nil, skinTempC: temp, steps: 999, bandState: band, activity: activity, spo2Pct: nil)
    }
    private func data(_ minutes: [ZoopAPI.Minute], now: Date? = nil, hours: [Int]? = nil) -> DayTimelineData {
        .init(minutes: minutes, day: day, now: now, sessions: [], walkingHours: hours, calendar: calendar)
    }
    func testClipsPastAndFutureWithoutExtendingTheLine() {
        let result = data([minute(-60), minute(60), minute(180), minute(86400)], now: day.addingTimeInterval(120))
        XCTAssertEqual(result.heartRate.map(\.date), [day.addingTimeInterval(60)])
        XCTAssertEqual(result.temperature.count, 1)
        XCTAssertNil(result.point(at: day.addingTimeInterval(180), metric: .heartRate))
    }
    func testGapsRemainSeparateAndAreNotSelectableReadings() {
        let result = data([minute(0), minute(60), minute(600)])
        XCTAssertEqual(result.heartRate.map(\.group), [0, 0, 1])
        XCTAssertEqual(result.heartRate.map(\.isolated), [false, false, true])
        XCTAssertNil(result.point(at: day.addingTimeInterval(300), metric: .heartRate))
        XCTAssertEqual(result.point(at: day.addingTimeInterval(50), metric: .heartRate)?.value, 60)
    }
    func testNullTemperatureDoesNotHideHeartRateOrFillItsGap() {
        let result = data([minute(0), minute(60, temp: nil), minute(120, temp: .nan), minute(180)])
        XCTAssertEqual(result.heartRate.count, 4)
        XCTAssertEqual(result.temperature.map(\.group), [0, 1])
    }
    func testTracksMergeOnlyAdjacentRecordedMinutes() {
        let result = data([minute(0, band: 2, activity: 1), minute(60, band: 2), minute(600, band: 2), minute(660, activity: 1)])
        XCTAssertEqual(result.events[.sleep]?.map(\.duration), [120, 60])
        XCTAssertEqual(result.events[.walk]?.map(\.start), [day.addingTimeInterval(660)])
    }
    func testFilteredHourBucketsIgnoreRawMinuteStepsAndFutureHours() {
        let result = data([minute(0)], now: day.addingTimeInterval(5400), hours: [123, 456, 789])
        XCTAssertEqual(result.hours.map(\.steps), [123, 456])
        XCTAssertEqual(result.hours.last?.end, day.addingTimeInterval(5400))
        XCTAssertEqual(result.hour(at: day.addingTimeInterval(4000))?.steps, 456)
        XCTAssertNil(result.hour(at: day.addingTimeInterval(6000)))
        XCTAssertTrue(data([minute(0)], hours: nil).hours.isEmpty)
    }
    func testDSTUsesWallClockHoursWithoutDuplicatingCounts() {
        var c = calendar; c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        for (month, date, expectedHours) in [(3, 29, 23), (10, 25, 25)] {
            let d = c.date(from: DateComponents(year: 2026, month: month, day: date))!
            let result = DayTimelineData(minutes: [], day: d, now: nil, sessions: [], walkingHours: Array(repeating: 10, count: 24), calendar: c)
            XCTAssertEqual(result.domain.upperBound.timeIntervalSince(result.domain.lowerBound), Double(expectedHours * 3600))
            XCTAssertEqual(result.hours.reduce(0) { $0 + $1.steps }, expectedHours == 23 ? 230 : 240)
            XCTAssertEqual(result.hours.map { $0.end.timeIntervalSince($0.start) }.reduce(0, +), Double(expectedHours * 3600))
            XCTAssertEqual(result.timeLabel(result.ticks[2]), "12:00")
            XCTAssertEqual(result.timeLabel(result.domain.upperBound), "24:00")
        }
    }
    func testScaleKeepsAllReadingsWithoutUnnecessaryZeroBaseline() {
        let scale = DayTimelineData.scale(values: [49, 60, 124], includesZero: false)
        XCTAssertEqual(scale.ticks, [50, 100, 150])
        XCTAssertLessThan(scale.domain.lowerBound, 49)
        XCTAssertGreaterThanOrEqual(scale.domain.upperBound, 124)
        XCTAssertEqual(DayTimelineData.scale(values: [0, 2000], includesZero: true).domain.lowerBound, 0)
    }
    func testWorkoutIntervalsAreUnionedWithoutBridgingRestGaps() {
        let spans = [DateInterval(start: day, duration: 120), DateInterval(start: day.addingTimeInterval(60), duration: 120), DateInterval(start: day.addingTimeInterval(600), duration: 60)]
        XCTAssertEqual(DayTimelineData.merged(spans).map(\.duration), [180, 60])
    }
}
