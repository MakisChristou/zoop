import Foundation
import XCTest
@testable import SnoopHealth

final class WeightTrendTests: XCTestCase {
    private func at(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }
    func testDailyPreferenceAndCalendarAverageAcrossDST() {
        let before = at("2025-03-03T12:00:00Z"), end = at("2025-03-09T12:00:00Z")
        let rows = [
            WeightReading(id: "own", measuredAt: end, kg: 100),
            WeightReading(id: "health:scale", measuredAt: end.addingTimeInterval(-60), kg: 80, source: "health", sourceName: "Scale"),
            WeightReading(id: "old", measuredAt: before, kg: 78),
            WeightReading(id: "outside", measuredAt: at("2025-03-02T23:00:00Z"), kg: 120),
            WeightReading(id: "removed", measuredAt: end, kg: 90, removed: true),
            WeightReading(id: "future", measuredAt: end.addingTimeInterval(3600), kg: 130)
        ]
        let trend = WeightTrend(rows, through: end, calendar: cal)
        XCTAssertEqual(trend.points.count, 3)
        XCTAssertEqual(trend.points.last?.reading.id, "health:scale")
        XCTAssertEqual(trend.points.last?.average, 79)
        XCTAssertEqual(trend.average(ending: end, calendar: cal), 79)
        // The first visible point still includes the preceding days in its average.
        XCTAssertEqual(trend.points.filter { $0.date >= cal.startOfDay(for: end) }.first?.average, 79)
    }
    func testSparseDaysDoNotInventValuesOrJoinLongGaps() {
        let first = at("2025-01-01T12:00:00Z"), next = at("2025-01-09T12:00:00Z")
        let trend = WeightTrend([WeightReading(measuredAt: next, kg: 82), WeightReading(measuredAt: first, kg: 80)], through: next, calendar: cal)
        XCTAssertEqual(trend.points.map(\.kg), [80, 82])
        XCTAssertEqual(trend.points.map(\.average), [80, 82])
        XCTAssertEqual(trend.points.map(\.segment), [0, 1])
        XCTAssertNil(trend.average(ending: at("2025-01-20T12:00:00Z"), calendar: cal))
    }
    func testPreviewDeduplicatesAndMatchesImportEligibility() {
        let start = at("2025-01-01T00:00:00Z"), end = at("2025-02-01T00:00:00Z")
        let a = WeightReading(id: "health:a", measuredAt: start, kg: 80, source: "health", sourceName: "Scale")
        let b = WeightReading(id: "health:b", measuredAt: start.addingTimeInterval(86400), kg: 81, source: "health", sourceName: "Scale")
        let preview = WeightImportPreview(readings: [a, a, b,
            WeightReading(measuredAt: start, kg: 80),
            WeightReading(id: "health:bad", measuredAt: start, kg: 500, source: "health"),
            WeightReading(id: "health:end", measuredAt: end, kg: 82, source: "health")
        ], savedIDs: [a.id], range: .init(from: start, to: end), now: end)
        XCTAssertEqual(preview.toImport, 1); XCTAssertEqual(preview.alreadySaved, 1)
        XCTAssertEqual(preview.first, a.measuredAt); XCTAssertEqual(preview.last, b.measuredAt)
    }
}
