import XCTest
@testable import Zoop

@MainActor final class TrendSleepSelectionTests: XCTestCase {
    func testExactWindowWinsAndNeverOpensANapOrRemovedSleep() {
        let summary = night(start: 100, end: 1000)
        let rows = [row(1, start: 100, end: 1000, kind: "nap"), row(2, start: 99, end: 1001), row(3, start: 100, end: 1000), row(4, start: 100, end: 1000, status: "removed")]
        XCTAssertEqual(TrendSleepDetailView.match(summary, in: rows)?.id, 3)
        XCTAssertNil(TrendSleepDetailView.match(summary, in: [rows[0], rows[3]]))
    }
    func testCorrectedWindowCanShiftButUnrelatedSleepIsNotSubstituted() {
        let summary = night(start: 100, end: 1000)
        XCTAssertEqual(TrendSleepDetailView.match(summary, in: [row(1, start: 160, end: 1060)])?.id, 1)
        XCTAssertNil(TrendSleepDetailView.match(summary, in: [row(1, start: 900, end: 1800)]))
        XCTAssertNil(TrendSleepDetailView.match(summary, in: []))
    }
    private func row(_ id: Int64, start: Double, end: Double, kind: String = "main", status: String = "active") -> ZoopAPI.SleepSession {
        .init(id: id, startTs: Date(timeIntervalSince1970: start), endTs: Date(timeIntervalSince1970: end), durationS: Int(end - start), kind: kind, edited: false, autoDetected: true, revision: 1, status: status, lastEdit: nil, replacements: [], metricsPending: false, timezone: "UTC", sleep: nil)
    }
    private func night(start: Double, end: Double) -> ZoopAPI.Night {
        .init(nightOf: "1970-01-01", algoVersion: 2, startTs: Date(timeIntervalSince1970: start), endTs: Date(timeIntervalSince1970: end), stages: [], metrics: .init(window: .init(onset: Date(timeIntervalSince1970: start), offset: Date(timeIntervalSince1970: end), timeInBedS: Int(end - start), asleepS: Int(end - start), wasoS: 0, efficiency: 1, coverageS: Int(end - start), disturbances: 0), physiology: .init(restingHr: nil, hrvRmssdMs: nil, hrvWindows: 0, respiratoryRate: nil, skinTempC: nil, spo2Pct: nil, spo2Windows: 0), stages: nil, naps: []))
    }
}
