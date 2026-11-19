import XCTest
@testable import ZoopHealth

final class WeightEntryPolicyTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/London")!
        return value
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    func testSameDayManualImportedAndPendingReadingsPreventAnotherEntry() {
        let start = date("2026-11-08T08:00:00Z")
        let candidate = WeightReading(id: "snoop:new", measuredAt: start.addingTimeInterval(3600), kg: 70)
        for source in ["snoop", "health"] {
            let existing = WeightReading(id: source + ":existing", measuredAt: start, kg: 71, source: source, version: 0)
            XCTAssertThrowsError(try WeightEntryPolicy.validate(candidate, existing: [existing], calendar: calendar)) {
                XCTAssertEqual($0 as? WeightEntryPolicy.Failure, .alreadyLogged)
            }
        }
    }

    func testEditingKeepsIdentityAndDoesNotRemoveOlderDuplicates() throws {
        let original = WeightReading(id: "snoop:existing", measuredAt: date("2026-11-08T08:00:00Z"), kg: 70, version: 2)
        var changed = original; changed.kg = 71
        let imported = WeightReading(id: "health:existing", measuredAt: original.measuredAt, kg: 72, source: "health")
        XCTAssertNoThrow(try WeightEntryPolicy.validate(changed, existing: [original, imported], calendar: calendar))
        changed.measuredAt = date("2026-11-09T08:00:00Z")
        XCTAssertNoThrow(try WeightEntryPolicy.validate(changed, existing: [original], calendar: calendar))
        let nextDay = WeightReading(measuredAt: changed.measuredAt, kg: 73)
        XCTAssertThrowsError(try WeightEntryPolicy.validate(changed, existing: [original, nextDay], calendar: calendar))
    }

    func testDeletionAllowsReplacementButImportedRowsCannotBeChanged() throws {
        var original = WeightReading(id: "snoop:existing", measuredAt: date("2026-11-08T08:00:00Z"), kg: 70)
        var deleted = original; deleted.removed = true
        XCTAssertNoThrow(try WeightEntryPolicy.validate(deleted, existing: [original], calendar: calendar))
        XCTAssertNoThrow(try WeightEntryPolicy.validate(WeightReading(measuredAt: original.measuredAt, kg: 72), existing: [deleted], calendar: calendar))
        original.source = "health"
        XCTAssertThrowsError(try WeightEntryPolicy.validate(original, existing: [original], calendar: calendar))
        // Changing an imported row's source must not bypass the protection.
        XCTAssertThrowsError(try WeightEntryPolicy.validate(deleted, existing: [original], calendar: calendar))
    }

    func testLocalCalendarDayAcrossMidnightAndDaylightSaving() throws {
        let before = WeightReading(measuredAt: date("2026-10-24T23:30:00Z"), kg: 70)
        let after = WeightReading(measuredAt: date("2026-10-25T23:30:00Z"), kg: 71)
        // The 25-hour local day includes both observations despite different UTC dates.
        XCTAssertThrowsError(try WeightEntryPolicy.validate(after, existing: [before], calendar: calendar))
        var tomorrow = after; tomorrow.measuredAt = date("2026-10-26T00:01:00Z")
        XCTAssertNoThrow(try WeightEntryPolicy.validate(tomorrow, existing: [before], calendar: calendar))
    }
}
