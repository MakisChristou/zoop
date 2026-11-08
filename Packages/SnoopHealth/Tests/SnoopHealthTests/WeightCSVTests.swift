import XCTest
@testable import SnoopHealth

final class WeightCSVTests: XCTestCase {
    func testExportsAllObservationsInOrderWithExplicitUnitsAndDates() {
        let date = Date(timeIntervalSince1970: 1_788_300_000)
        let first = WeightReading(id: "health:one", measuredAt: date, kg: 62.85, source: "health", sourceName: "Scale")
        let second = WeightReading(id: "snoop:two", measuredAt: date.addingTimeInterval(60), kg: 63.1)
        let csv = WeightCSV.encode([second, WeightReading(kg: 80, removed: true), first], timeZone: TimeZone(secondsFromGMT: 7200)!)
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0], "measured_at_utc,local_date,time_zone,weight_kg,source,source_name,reading_id")
        XCTAssertTrue(lines[1].contains("\"62.85\",\"health\",\"Scale\",\"health:one\""))
        XCTAssertTrue(lines[2].contains("\"63.1\",\"snoop\""))
        XCTAssertTrue(lines[1].contains("Z\""))
        XCTAssertFalse(csv.contains("80.0"))
    }

    func testEscapesQuotesCommasNewlinesAndSpreadsheetFormulas() {
        let rows = [WeightReading(id: "one", measuredAt: .distantPast, kg: 70, sourceName: "Scale, \"Home\"\nBedroom"),
                    WeightReading(id: "two", kg: 71, sourceName: "=1+1")]
        let csv = WeightCSV.encode(rows)
        XCTAssertTrue(csv.contains("\"Scale, \"\"Home\"\"\nBedroom\""))
        XCTAssertTrue(csv.contains("\"'=1+1\""))
    }

    func testEmptyExportAndNonfiniteWeightsHaveOnlyHeader() {
        XCTAssertEqual(WeightCSV.encode([]), WeightCSV.encode([WeightReading(kg: .nan), WeightReading(kg: .infinity)]))
        XCTAssertEqual(WeightCSV.encode([]).components(separatedBy: "\r\n").count, 2)
    }

    func testLocalDayDoesNotChangeTheMeasurementTimestamp() {
        let date = ISO8601DateFormatter().date(from: "2026-11-07T23:30:00Z")!
        let csv = WeightCSV.encode([WeightReading(measuredAt: date, kg: 70)], timeZone: TimeZone(identifier: "Asia/Nicosia")!)
        XCTAssertTrue(csv.contains("\"2026-11-07T23:30:00.000Z\",\"2026-11-08\",\"Asia/Nicosia\",\"70.0\""))
    }
}
