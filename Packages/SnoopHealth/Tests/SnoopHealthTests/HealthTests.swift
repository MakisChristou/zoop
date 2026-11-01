import Foundation
import XCTest
@testable import SnoopHealth

final class HealthTests: XCTestCase {
    private func at(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }
    private func record(id: String = "sleep:1", end: Date, version: Int64 = 1, removed: Bool = false) -> HealthRecord {
        HealthRecord(id: id, domain: "sleep", version: version, sequence: version, startTs: end.addingTimeInterval(-3600), endTs: end, payload: .init(kind: "main", intervals: [], count: nil, kg: nil), removed: removed)
    }
    func testConnectionBoundaryAndHistoricalConsent() {
        var j = HealthJournal(); let start = at("2025-03-09T08:00:00Z"); j.connectedAt = start
        XCTAssertFalse(j.eligible(record(end: start.addingTimeInterval(-1))))
        XCTAssertTrue(j.eligible(record(end: start)))
        let range = HealthJournal.Range(from: start.addingTimeInterval(-86400), to: start)
        j.backfill(range); j.backfill(range)
        XCTAssertEqual(j.ranges.count, 1); XCTAssertEqual(j.connectedAt, start)
        XCTAssertTrue(j.eligible(record(end: start.addingTimeInterval(-100))))
    }
    func testCorrectionsStayEnrolledOutsideOriginalWindow() {
        var j = HealthJournal(); let end = at("2025-01-02T08:00:00Z"); j.connectedAt = end
        j.acknowledge(record(end: end)); j.cursor = 15
        XCTAssertTrue(j.eligible(record(end: end.addingTimeInterval(-86400), version: 2)))
        j.deferred["sleep:1"] = record(end: end, version: 2)
        let restored = try! JSONDecoder().decode(HealthJournal.self, from: JSONEncoder().encode(j))
        XCTAssertEqual(restored.cursor, 15); XCTAssertEqual(restored.versions["sleep:1"], 1)
        XCTAssertEqual(restored.deferred["sleep:1"]?.version, 2)
    }
    func testWeightsPreferExternalAndNeverInventMissingDays() {
        let d = at("2025-03-09T12:00:00Z")
        let rows = [WeightReading(measuredAt: d, kg: 80), WeightReading(id: "health:scale", measuredAt: d.addingTimeInterval(-600), kg: 79, source: "health", sourceName: "Scale"), WeightReading(measuredAt: d.addingTimeInterval(-86400), kg: 77)]
        XCTAssertEqual(WeightReading.preferred(rows, on: d, calendar: calendar)?.kg, 79)
        XCTAssertEqual(WeightReading.trend(rows, ending: d, calendar: calendar), 78)
        XCTAssertNil(WeightReading.preferred(rows, on: d.addingTimeInterval(86400), calendar: calendar))
    }
    func testReminderRequiresFreshConfirmedWakeAndNoWeight() {
        let now = at("2025-03-09T12:00:00Z"), enabled = at("2025-03-08T00:00:00Z")
        let wake = now.addingTimeInterval(-1800)
        XCTAssertEqual(WeightReminderPolicy.delivery(now: now, confirmedWake: wake, enabledAt: enabled, hasWeight: false, alreadyReminded: false, calendar: calendar), now.addingTimeInterval(300))
        XCTAssertNil(WeightReminderPolicy.delivery(now: now, confirmedWake: wake, enabledAt: enabled, hasWeight: true, alreadyReminded: false, calendar: calendar))
        XCTAssertNil(WeightReminderPolicy.delivery(now: now, confirmedWake: wake, enabledAt: enabled, hasWeight: false, alreadyReminded: true, calendar: calendar))
        XCTAssertNil(WeightReminderPolicy.delivery(now: now, confirmedWake: nil, enabledAt: enabled, hasWeight: false, alreadyReminded: false, calendar: calendar))
        XCTAssertNil(WeightReminderPolicy.delivery(now: now, confirmedWake: now.addingTimeInterval(-10801), enabledAt: enabled, hasWeight: false, alreadyReminded: false, calendar: calendar))
    }
    func testStepBackfillIncludesTheLastMinuteOfTheChosenDay() {
        let midnight = at("2025-01-02T00:00:00Z")
        var j = HealthJournal(); j.connectedAt = midnight.addingTimeInterval(86400)
        j.backfill(.init(from: midnight.addingTimeInterval(-86400), to: midnight))
        let step = HealthRecord(id: "steps:1", domain: "steps", version: 1, sequence: 1,
                               startTs: midnight.addingTimeInterval(-60), endTs: midnight,
                               payload: .init(kind: nil, intervals: nil, count: 60, kg: nil), removed: false)
        XCTAssertTrue(j.eligible(step))
        XCTAssertFalse(j.eligible(record(end: midnight)))
    }
    func testPastWakeAndSameDayImportRulesAcrossDST() {
        let now = at("2025-03-10T04:30:00Z") // 00:30, after spring transition
        XCTAssertNil(WeightReminderPolicy.delivery(now: now, confirmedWake: now.addingTimeInterval(-3600), enabledAt: now.addingTimeInterval(-86400), hasWeight: false, alreadyReminded: false, calendar: calendar))
        XCTAssertNil(WeightReminderPolicy.delivery(now: now, confirmedWake: now.addingTimeInterval(-60), enabledAt: now, hasWeight: false, alreadyReminded: false, calendar: calendar))
        let old = WeightReading(id: "health:old", measuredAt: now.addingTimeInterval(-3600), kg: 80, source: "health", sourceName: "Scale")
        XCTAssertNil(WeightReading.preferred([old], on: now, calendar: calendar))
    }
}
