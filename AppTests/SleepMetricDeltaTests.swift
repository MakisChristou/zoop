import XCTest
@testable import Snoop

final class SleepMetricDeltaTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private var baseline: MorningInsights.Baseline { .init(state: "early", count: 7, from: "2026-10-25", to: "2026-10-31", average: nil, lower: nil, upper: nil) }
    private func row(_ day: String, id: Int64, efficiency: Double? = 0.92, pending: Bool = false, kind: String = "main", status: String = "active", coverage: Int = 28800, temperature: Double? = 32.2, breathing: Double? = 14.5, oxygen: Double? = 98, awake: Int = 1800, revision: Int64 = 1) -> SnoopAPI.SleepSession {
        let n = TrendStoreTests.night(day: day), w = n.metrics.window
        return .init(id: id, startTs: n.startTs, endTs: n.endTs, durationS: 28800, kind: kind, edited: false, autoDetected: true, revision: revision, status: status, lastEdit: nil, replacements: [], metricsPending: pending, timezone: "UTC", sleep: .init(window: .init(onset: w.onset, offset: w.offset, timeInBedS: w.timeInBedS, asleepS: w.asleepS, wasoS: awake, efficiency: w.efficiency, coverageS: coverage, disturbances: 1), physiology: .init(restingHr: 52, hrvRmssdMs: 66, hrvWindows: 40, respiratoryRate: breathing, skinTempC: temperature, spo2Pct: oxygen, spo2Windows: oxygen == nil ? 0 : 10), stages: nil, segments: [], algoVersion: 2, efficiency: efficiency, unknownS: nil, unclassifiedS: nil))
    }
    private var history: [SnoopAPI.SleepSession] { (0..<7).map { row("2026-10-\(25 + $0)", id: Int64($0 + 1)) } }
    func testEfficiencyUsesRelativePercentAndExcludesCurrentNight() {
        let current = row("2026-11-04", id: 20, efficiency: 0.93)
        let result = SleepMetricDelta.efficiency(record: current, history: history + [current], baseline: baseline, calendar: calendar)
        XCTAssertEqual(result?.text, "+1.1%")
        XCTAssertEqual(result?.signal, "favourable")
        XCTAssertEqual(SleepMetricDelta.efficiency(record: row("2026-11-04", id: 20), history: history, baseline: baseline, calendar: calendar)?.text, "0%")
    }
    func testInsufficientMissingPendingNapAndLowCoverageDoNotInventComparisons() {
        let current = row("2026-11-04", id: 20, efficiency: 0.93)
        for extra in [row("2026-10-31", id: 7, efficiency: nil), row("2026-10-31", id: 7, pending: true), row("2026-10-31", id: 7, kind: "nap"), row("2026-10-31", id: 7, status: "removed"), row("2026-10-31", id: 7, coverage: 300)] {
            XCTAssertNil(SleepMetricDelta.efficiency(record: current, history: Array(history.prefix(6)) + [extra], baseline: baseline, calendar: calendar))
        }
        XCTAssertNil(SleepMetricDelta.efficiency(record: row("2026-11-04", id: 20, pending: true), history: history, baseline: baseline, calendar: calendar))
        XCTAssertEqual(SleepMetricDelta.efficiency(record: current, history: history, baseline: nil, calendar: calendar)?.text, "+1.1%")
    }
    func testDuplicateDayDoesNotSatisfyMinimumAndNegativeDeltaIsUnfavourable() {
        let current = row("2026-11-04", id: 20, efficiency: 0.89)
        XCTAssertNil(SleepMetricDelta.efficiency(record: current, history: Array(history.prefix(6)) + [row("2026-10-25", id: 99)], baseline: baseline, calendar: calendar))
        let result = SleepMetricDelta.efficiency(record: current, history: history, baseline: baseline, calendar: calendar)
        XCTAssertEqual(result?.text, "−3.3%"); XCTAssertEqual(result?.signal, "unfavourable")
    }

    func testRHRAndHRVColoursFollowDirectionEvenWithinUsualRange() {
        func metric(_ key: String, _ delta: Double, signal: String? = nil) -> MorningInsights.Metric {
            .init(key: key, value: 50, quality: "good", baseline: baseline, relation: "similar",
                  comparison: .init(delta: delta, unit: key == "hrv" ? "percent" : "bpm", signal: signal),
                  history: [], week: .init(count: 7, average: 50, previousAverage: 50))
        }
        XCTAssertEqual(SleepMetricDelta.comparison(metric("resting_hr", 1))?.signal, "unfavourable")
        XCTAssertEqual(SleepMetricDelta.comparison(metric("resting_hr", -1, signal: "usual"))?.signal, "favourable")
        XCTAssertEqual(SleepMetricDelta.comparison(metric("hrv", 5, signal: "usual"))?.signal, "favourable")
        XCTAssertEqual(SleepMetricDelta.comparison(metric("hrv", -5))?.signal, "unfavourable")
        XCTAssertNil(SleepMetricDelta.comparison(metric("hrv", .nan)))
    }

    func testTemperatureUsesDegreesAndOtherVitalsHaveNeutralPercentDeltas() {
        let current = row("2026-11-04", id: 20, temperature: 32.5, breathing: 15.95, oxygen: 97, awake: 900)
        func delta(_ metric: SleepMetricDelta.Metric) -> SleepMetricDelta? {
            SleepMetricDelta.nightly(metric, record: current, history: history, baseline: baseline, calendar: calendar)
        }
        XCTAssertEqual(delta(.temperature)?.text, "+0.3 °C")
        XCTAssertNil(delta(.temperature)?.signal)
        XCTAssertEqual(delta(.breathing)?.text, "+10%")
        XCTAssertNil(delta(.breathing)?.signal)
        XCTAssertEqual(delta(.oxygen)?.text, "−1%")
        XCTAssertNil(delta(.oxygen)?.signal)
        XCTAssertEqual(delta(.awake)?.text, "−50%")
        XCTAssertEqual(delta(.awake)?.signal, "favourable")
    }

    func testMissingVitalDoesNotBecomeZeroAndNewestInvalidRevisionWins() {
        let current = row("2026-11-04", id: 20, temperature: 32.5)
        for replacement in [row("2026-10-31", id: 7, temperature: nil, revision: 2),
                            row("2026-10-31", id: 7, pending: true, revision: 2)] {
            XCTAssertNil(SleepMetricDelta.nightly(.temperature, record: current, history: history + [replacement], baseline: baseline, calendar: calendar))
        }
        XCTAssertNil(SleepMetricDelta.nightly(.temperature, record: row("2026-11-04", id: 20, temperature: .nan), history: history, baseline: baseline, calendar: calendar))
        XCTAssertNil(SleepMetricDelta.nightly(.oxygen, record: row("2026-11-04", id: 20, oxygen: nil), history: history, baseline: baseline, calendar: calendar))
    }

    func testFutureNightsAndZeroBaselinesCannotInventPercentages() {
        let current = row("2026-11-04", id: 20)
        let future = (5...12).map { row(String(format: "2026-11-%02d", $0), id: Int64($0 + 50)) }
        XCTAssertNil(SleepMetricDelta.nightly(.temperature, record: current, history: future, baseline: nil, calendar: calendar))
        let zero = (25...31).map { row("2026-10-\($0)", id: Int64($0), awake: 0) }
        XCTAssertNil(SleepMetricDelta.nightly(.awake, record: current, history: zero, baseline: baseline, calendar: calendar))
    }
}
