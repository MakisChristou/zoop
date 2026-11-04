import XCTest
@testable import SnoopData

final class TrendSelectionTests: XCTestCase {
    func testSelectionUsesRecordedValuesAcrossGapsAndBounds() throws {
        let series = TrendSeries([point(100, 8), point(10, 6), point(30, 7)])
        for (time, index) in [(-100.0, 0), (10, 0), (20, 0), (21, 1), (65, 1), (66, 2), (1000, 2)] {
            let selected = try XCTUnwrap(series.nearestIndex(to: Date(timeIntervalSince1970: time)))
            XCTAssertEqual(selected, index)
            XCTAssertEqual(series.points[selected].value, [6, 7, 8][index])
        }
    }
    func testEmptySingleAndRepeatedTimestamps() {
        XCTAssertNil(TrendSeries([]).nearestIndex(to: .now))
        XCTAssertEqual(TrendSeries([point(10, 7)]).nearestIndex(to: .distantPast), 0)
        XCTAssertEqual(TrendSeries([point(10, 7)]).nearestIndex(to: .distantFuture), 0)
        XCTAssertEqual(TrendSeries([point(10, 7), point(10, 8), point(20, 9)]).nearestIndex(to: Date(timeIntervalSince1970: 10)), 0)
    }
    func testSelectionAcrossDaylightSavingUsesActualInstants() throws {
        let dates = try APIDateCoding.decoder().decode([Date].self, from: Data("[\"2026-10-25T02:30:00+02:00\",\"2026-10-25T02:30:00+01:00\"]".utf8))
        let series = TrendSeries(zip(dates, [6.0, 8]).map { TrendPoint(date: $0, value: $1) })
        XCTAssertEqual(series.nearestIndex(to: dates[0].addingTimeInterval(1800)), 0)
        XCTAssertEqual(series.nearestIndex(to: dates[0].addingTimeInterval(1801)), 1)
    }
    func testLineBreaksAtMissingDaysAcrossDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let dates = try APIDateCoding.decoder().decode([Date].self, from: Data("[\"2026-10-24T08:00:00+02:00\",\"2026-10-25T08:00:00+01:00\",\"2026-10-27T08:00:00+01:00\"]".utf8))
        let series = TrendSeries(dates.map { TrendPoint(date: $0, value: 8) }, calendar: calendar)
        XCTAssertEqual(series.segmentByDate[dates[0]], series.segmentByDate[dates[1]])
        XCTAssertNotEqual(series.segmentByDate[dates[1]], series.segmentByDate[dates[2]])
    }
    private func point(_ time: Double, _ value: Double) -> TrendPoint { .init(date: Date(timeIntervalSince1970: time), value: value) }
}
