import XCTest
@testable import Snoop

final class SleepMetricDeltaTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private var baseline: MorningInsights.Baseline { .init(state: "early", count: 7, from: "2026-10-25", to: "2026-10-31", average: nil, lower: nil, upper: nil) }
    private func row(_ day: String, id: Int64, efficiency: Double? = 0.92, pending: Bool = false, kind: String = "main", status: String = "active", coverage: Int = 28800) -> SnoopAPI.SleepSession {
        let n = TrendStoreTests.night(day: day), w = n.metrics.window
        return .init(id: id, startTs: n.startTs, endTs: n.endTs, durationS: 28800, kind: kind, edited: false, autoDetected: true, revision: 1, status: status, lastEdit: nil, replacements: [], metricsPending: pending, timezone: "UTC", sleep: .init(window: .init(onset: w.onset, offset: w.offset, timeInBedS: w.timeInBedS, asleepS: w.asleepS, wasoS: w.wasoS, efficiency: w.efficiency, coverageS: coverage, disturbances: 1), physiology: n.metrics.physiology, stages: nil, segments: [], algoVersion: 2, efficiency: efficiency, unknownS: nil, unclassifiedS: nil))
    }
    private var history: [SnoopAPI.SleepSession] { (0..<7).map { row("2026-10-\(25 + $0)", id: Int64($0 + 1)) } }
    func testEfficiencyUsesPercentagePointsAndExcludesCurrentNight() {
        let current = row("2026-11-04", id: 20, efficiency: 0.93)
        let result = SleepMetricDelta.efficiency(record: current, history: history + [current], baseline: baseline, calendar: calendar)
        XCTAssertEqual(result?.text, "+1 pt")
        XCTAssertEqual(result?.signal, "favourable")
        XCTAssertNil(SleepMetricDelta.efficiency(record: row("2026-11-04", id: 20), history: history, baseline: baseline, calendar: calendar))
    }
    func testInsufficientMissingPendingNapAndLowCoverageDoNotInventComparisons() {
        let current = row("2026-11-04", id: 20, efficiency: 0.93)
        for extra in [row("2026-10-31", id: 7, efficiency: nil), row("2026-10-31", id: 7, pending: true), row("2026-10-31", id: 7, kind: "nap"), row("2026-10-31", id: 7, status: "removed"), row("2026-10-31", id: 7, coverage: 300)] {
            XCTAssertNil(SleepMetricDelta.efficiency(record: current, history: Array(history.prefix(6)) + [extra], baseline: baseline, calendar: calendar))
        }
        XCTAssertNil(SleepMetricDelta.efficiency(record: row("2026-11-04", id: 20, pending: true), history: history, baseline: baseline, calendar: calendar))
        XCTAssertNil(SleepMetricDelta.efficiency(record: current, history: history, baseline: nil, calendar: calendar))
    }
    func testDuplicateDayDoesNotSatisfyMinimumAndNegativeDeltaIsUnfavourable() {
        let current = row("2026-11-04", id: 20, efficiency: 0.89)
        XCTAssertNil(SleepMetricDelta.efficiency(record: current, history: Array(history.prefix(6)) + [row("2026-10-25", id: 99)], baseline: baseline, calendar: calendar))
        let result = SleepMetricDelta.efficiency(record: current, history: history, baseline: baseline, calendar: calendar)
        XCTAssertEqual(result?.text, "−3 pt"); XCTAssertEqual(result?.signal, "unfavourable")
    }
}
