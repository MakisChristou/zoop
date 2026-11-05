import XCTest
@testable import Snoop

final class SleepMetricDeltaTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private func row(_ day: String, id: Int64, efficiency: Double? = 0.92, pending: Bool = false, kind: String = "main", status: String = "active", coverage: Int = 28800, temperature: Double? = 32.2, breathing: Double? = 14.5, oxygen: Double? = 98, awake: Int = 1800, revision: Int64 = 1, restingHR: Double? = 52, hrv: Double? = 66, hrvWindows: Int = 40) -> SnoopAPI.SleepSession {
        let n = TrendStoreTests.night(day: day), w = n.metrics.window
        return .init(id: id, startTs: n.startTs, endTs: n.endTs, durationS: 28800, kind: kind, edited: false, autoDetected: true, revision: revision, status: status, lastEdit: nil, replacements: [], metricsPending: pending, timezone: "UTC", sleep: .init(window: .init(onset: w.onset, offset: w.offset, timeInBedS: w.timeInBedS, asleepS: w.asleepS, wasoS: awake, efficiency: w.efficiency, coverageS: coverage, disturbances: 1), physiology: .init(restingHr: restingHR, hrvRmssdMs: hrv, hrvWindows: hrvWindows, respiratoryRate: breathing, skinTempC: temperature, spo2Pct: oxygen, spo2Windows: oxygen == nil ? 0 : 10), stages: nil, segments: [], algoVersion: 2, efficiency: efficiency, unknownS: nil, unclassifiedS: nil))
    }
    private var history: [SnoopAPI.SleepSession] { (0..<7).map { row("2026-10-\(25 + $0)", id: Int64($0 + 1)) } }
    func testEfficiencyUsesRelativePercentAndExcludesCurrentNight() {
        let current = row("2026-11-04", id: 20, efficiency: 0.93)
        let result = SleepMetricDelta.nightly(.efficiency, record: current, history: history + [current], calendar: calendar)
        XCTAssertEqual(result?.text, "+1.1%")
        XCTAssertEqual(result?.signal, "favourable")
        XCTAssertEqual(SleepMetricDelta.nightly(.efficiency, record: row("2026-11-04", id: 20), history: history, calendar: calendar)?.text, "0%")
    }
    func testInsufficientMissingPendingNapAndLowCoverageDoNotInventComparisons() {
        let current = row("2026-11-04", id: 20, efficiency: 0.93)
        for extra in [row("2026-10-31", id: 7, efficiency: nil), row("2026-10-31", id: 7, pending: true), row("2026-10-31", id: 7, kind: "nap"), row("2026-10-31", id: 7, status: "removed"), row("2026-10-31", id: 7, coverage: 300)] {
            XCTAssertNil(SleepMetricDelta.nightly(.efficiency, record: current, history: Array(history.prefix(6)) + [extra], calendar: calendar))
        }
        XCTAssertNil(SleepMetricDelta.nightly(.efficiency, record: row("2026-11-04", id: 20, pending: true), history: history, calendar: calendar))
        XCTAssertEqual(SleepMetricDelta.nightly(.efficiency, record: current, history: history, calendar: calendar)?.text, "+1.1%")
    }
    func testDuplicateDayDoesNotSatisfyMinimumAndNegativeDeltaIsUnfavourable() {
        let current = row("2026-11-04", id: 20, efficiency: 0.89)
        XCTAssertNil(SleepMetricDelta.nightly(.efficiency, record: current, history: Array(history.prefix(6)) + [row("2026-10-25", id: 99)], calendar: calendar))
        let result = SleepMetricDelta.nightly(.efficiency, record: current, history: history, calendar: calendar)
        XCTAssertEqual(result?.text, "−3.3%"); XCTAssertEqual(result?.signal, "unfavourable")
    }

    func testRHRAndHRVUseNightHistoryWithoutAnyInsightsResponse() {
        let current = row("2026-11-04", id: 20, restingHR: 53, hrv: 69.3)
        let result = SleepMetricDelta.all(record: current, history: history, calendar: calendar)
        XCTAssertEqual(result[.restingHR]?.text, "+1 bpm")
        XCTAssertEqual(result[.restingHR]?.signal, "unfavourable")
        XCTAssertEqual(result[.hrv]?.text, "+5%")
        XCTAssertEqual(result[.hrv]?.signal, "favourable")
        let lower = SleepMetricDelta.all(record: row("2026-11-04", id: 20, restingHR: 51, hrv: 62.7), history: history, calendar: calendar)
        XCTAssertEqual(lower[.restingHR]?.signal, "favourable")
        XCTAssertEqual(lower[.hrv]?.signal, "unfavourable")
        let unchanged = SleepMetricDelta.all(record: row("2026-11-04", id: 20), history: history, calendar: calendar)
        XCTAssertEqual(unchanged[.restingHR]?.text, "0 bpm")
        XCTAssertEqual(unchanged[.hrv]?.text, "0%")
        XCTAssertNil(unchanged[.restingHR]?.signal)
    }

    func testCardiacMissingDataAndQualityAreRespectedPerMetric() {
        let current = row("2026-11-04", id: 20, restingHR: nil, hrvWindows: 0)
        let result = SleepMetricDelta.all(record: current, history: history, calendar: calendar)
        XCTAssertNil(result[.restingHR]); XCTAssertNil(result[.hrv])
        XCTAssertNotNil(result[.temperature])
        let missing = Array(history.prefix(6)) + [row("2026-10-31", id: 7, hrv: nil)]
        let comparison = SleepMetricDelta.all(record: row("2026-11-04", id: 20), history: missing, calendar: calendar)
        XCTAssertNil(comparison[.hrv]); XCTAssertNotNil(comparison[.restingHR])
    }

    func testTemperatureUsesDegreesAndOtherVitalsHaveNeutralPercentDeltas() {
        let current = row("2026-11-04", id: 20, temperature: 32.5, breathing: 15.95, oxygen: 97, awake: 900)
        func delta(_ metric: SleepMetricDelta.Metric) -> SleepMetricDelta? {
            SleepMetricDelta.nightly(metric, record: current, history: history, calendar: calendar)
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
            XCTAssertNil(SleepMetricDelta.nightly(.temperature, record: current, history: history + [replacement], calendar: calendar))
        }
        XCTAssertNil(SleepMetricDelta.nightly(.temperature, record: row("2026-11-04", id: 20, temperature: .nan), history: history, calendar: calendar))
        XCTAssertNil(SleepMetricDelta.nightly(.oxygen, record: row("2026-11-04", id: 20, oxygen: nil), history: history, calendar: calendar))
    }

    func testFutureNightsAndZeroBaselinesCannotInventPercentages() {
        let current = row("2026-11-04", id: 20)
        let future = (5...12).map { row(String(format: "2026-11-%02d", $0), id: Int64($0 + 50)) }
        XCTAssertNil(SleepMetricDelta.nightly(.temperature, record: current, history: future, calendar: calendar))
        let zero = (25...31).map { row("2026-10-\($0)", id: Int64($0), awake: 0) }
        XCTAssertNil(SleepMetricDelta.nightly(.awake, record: current, history: zero, calendar: calendar))
        XCTAssertEqual(SleepMetricDelta.nightly(.awake, record: row("2026-11-04", id: 20, awake: 0), history: zero, calendar: calendar)?.text, "0%")
    }
}
