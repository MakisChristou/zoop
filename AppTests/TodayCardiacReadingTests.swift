import XCTest
@testable import Zoop

final class TodayCardiacReadingTests: XCTestCase {
    private func physiology(windows: Int = 30, hrv: Double? = 83, hr: Double? = 50) -> ZoopAPI.Night.Physiology {
        .init(restingHr: hr, hrvRmssdMs: hrv, hrvWindows: windows, respiratoryRate: nil, skinTempC: nil, spo2Pct: nil, spo2Windows: 0)
    }
    private func insights(state: String, value: String = "72") throws -> MorningInsights {
        let json = """
        {"version":2,"day":"2026-11-20","timezone":"UTC","state":"\(state)",
         "metrics":[{"key":"hrv","value":\(value),"quality":"good","baseline":{"state":"early","count":10,"from":"2026-11-01","to":"2026-11-19"},
                     "comparison":{"delta":5,"unit":"percent","signal":"favourable"},"history":[],"week":{"count":7}}],
         "observations":[],"timing":{"count":0}}
        """
        return try JSONDecoder().decode(MorningInsights.self, from: Data(json.utf8))
    }
    func testNoOutlookStillShowsNightlyMeasurementsWithoutComparisons() {
        let hrv = TodayCardiacReading(key: "hrv", insights: nil, physiology: physiology())
        XCTAssertEqual(hrv.value, 83); XCTAssertNil(hrv.metric)
        XCTAssertEqual(TodayCardiacReading(key: "resting_hr", insights: nil, physiology: physiology()).value, 50)
    }
    func testPendingOutlookDoesNotUseStaleValuesOrComparisons() throws {
        for state in ["updating", "awaiting_sync"] {
            let reading = TodayCardiacReading(key: "hrv", insights: try insights(state: state), physiology: physiology())
            XCTAssertEqual(reading.value, 83); XCTAssertNil(reading.metric)
        }
    }
    func testAvailableOutlookReadingKeepsItsOwnComparison() throws {
        for state in ["ready", "learning", "limited"] {
            let reading = TodayCardiacReading(key: "hrv", insights: try insights(state: state), physiology: physiology())
            XCTAssertEqual(reading.value, 72); XCTAssertEqual(reading.metric?.comparison?.delta, 5)
        }
    }
    func testMissingOutlookMetricFallsBackIndependently() throws {
        let reading = TodayCardiacReading(key: "resting_hr", insights: try insights(state: "ready"), physiology: physiology())
        XCTAssertEqual(reading.value, 50); XCTAssertNil(reading.metric)
        XCTAssertEqual(TodayCardiacReading(key: "hrv", insights: try insights(state: "ready", value: "null"), physiology: physiology()).value, 83)
    }
    func testMissingOrInvalidNightlyReadingsAreNotFabricated() {
        XCTAssertNil(TodayCardiacReading(key: "hrv", insights: nil, physiology: nil).value)
        XCTAssertNil(TodayCardiacReading(key: "hrv", insights: nil, physiology: physiology(windows: 0)).value)
        XCTAssertNil(TodayCardiacReading(key: "hrv", insights: nil, physiology: physiology(hrv: .nan)).value)
        XCTAssertNil(TodayCardiacReading(key: "resting_hr", insights: nil, physiology: physiology(hr: 0)).value)
    }
}
