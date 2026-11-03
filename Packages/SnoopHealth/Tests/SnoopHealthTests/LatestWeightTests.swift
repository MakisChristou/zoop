import XCTest
@testable import SnoopHealth

final class LatestWeightTests: XCTestCase {
    func testCurrentWeightUsesMeasurementDateAndHealthPriority() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_780_000_000), today = calendar.startOfDay(for: now)
        let health = WeightReading(id: "health:current", measuredAt: today, kg: 75, source: "health", sourceName: "Scale")
        let rows = [WeightReading(measuredAt: today.addingTimeInterval(60),kg: 85), health,
                    WeightReading(measuredAt: today.addingTimeInterval(-86400),kg: 80),
                    WeightReading(measuredAt: now.addingTimeInterval(86400),kg: 100),
                    WeightReading(measuredAt: now,kg: 90,removed: true)]
        XCTAssertEqual(WeightReading.latest(rows,now: now,calendar: calendar)?.id,health.id)
        let next = WeightReading(measuredAt: today.addingTimeInterval(86400),kg: 74)
        XCTAssertEqual(WeightReading.latest(rows.prefix(3) + [next],now: next.measuredAt,calendar: calendar)?.id,next.id)
        XCTAssertNil(WeightReading.latest([WeightReading(kg: .nan),WeightReading(kg: 999)]))
    }
}
