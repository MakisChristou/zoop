import XCTest
@testable import Zoop

final class WidgetSnapshotTests: XCTestCase {
    func testSwitchingScopeDropsAllPreviousReadings() {
        let saved = WidgetSnapshot(owner: "a", sleepSeconds: 5400, load: 12, steps: 8000, stepsGoal: 10000,
                                   recovery: [.init(day: Date(), score: 74, band: "high")], latestKg: 72)
        XCTAssertEqual(saved.scoped(to: "a"), saved)
        XCTAssertEqual(saved.scoped(to: "b"), WidgetSnapshot(owner: "b"))
    }

    func testNextDayCannotInheritThePreviousDaysRings() {
        let first = Date(timeIntervalSince1970: 0)
        var saved = WidgetSnapshot(day: first, sleepSeconds: 1234, sleepFraction: 0.2,
                                   load: 4, loadFraction: 0.19, latestKg: 73)
        saved.beginDay(first)
        XCTAssertEqual(saved.load, 4)
        saved.beginDay(first.addingTimeInterval(86400))
        XCTAssertNil(saved.sleepSeconds)
        XCTAssertNil(saved.sleepFraction)
        XCTAssertNil(saved.load)
        XCTAssertNil(saved.loadFraction)
        XCTAssertEqual(saved.latestKg, 73)
    }
    func testStepsProgressUsesTheDayAndGoalWithoutCappingTheCount() throws {
        let day = Date(timeIntervalSince1970: 86_400)
        var value = WidgetSnapshot(day: day, steps: 8000, stepsGoal: 10000)
        XCTAssertEqual(value.stepsReading(on: day)?.fraction, 0.8)
        value.steps = 12500
        XCTAssertEqual(value.stepsReading(on: day)?.fraction, 1)
        XCTAssertEqual(value.stepsReading(on: day)?.count, 12500)
        value.steps = 0
        XCTAssertEqual(value.stepsReading(on: day)?.fraction, 0)
        value.stepsGoal = nil
        XCTAssertEqual(value.stepsReading(on: day)?.count, 0)
        XCTAssertNil(value.stepsReading(on: day)?.fraction)
        let tomorrow = day.addingTimeInterval(86400)
        XCTAssertNil(value.stepsReading(on: tomorrow))
        value.beginDay(tomorrow)
        XCTAssertNil(value.steps)
        XCTAssertNil(value.stepsGoal)

        let oldData = Data(#"{"owner":"a","recovery":[],"weights":[],"unit":"kg"}"#.utf8)
        let old = try JSONDecoder().decode(WidgetSnapshot.self, from: oldData)
        XCTAssertNil(old.steps)
        XCTAssertEqual(old.owner, "a")
    }

    func testHistoryCalendarAndLoadBucketsMatchTheDashboard() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Nicosia"))
        let today = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 26)))
        let grid = WidgetHistory.heatmapDays(through: today, calendar: cal)
        XCTAssertEqual(grid.count, 140)
        XCTAssertEqual(cal.component(.weekday, from: grid[0]), 2)
        XCTAssertEqual(grid.filter { $0 > today }.count, 3)
        XCTAssertEqual(Set(grid).count, grid.count)
        let dates = WidgetHistory.calendarDays(ending: today, count: 30, calendar: cal)
        XCTAssertEqual(dates.last, today)
        XCTAssertEqual(cal.component(.day, from: dates[0]), 28)
        XCTAssertEqual([0, 0.1, 4.2, 4.21, 8.4, 16.8, 21, 22].map(WidgetHistory.loadLevel), [0,1,1,2,2,4,5,5])
        let saved = WidgetSnapshot.ActivityHistory(refreshed: today, zone: cal.timeZone.identifier, loads: [today: 0])
        XCTAssertTrue(saved.isFresh(on: today, calendar: cal))
        XCTAssertFalse(saved.isFresh(on: dates[0], calendar: cal))
        var utc = cal
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertFalse(saved.isFresh(on: today, calendar: utc))
        let snapshot = WidgetSnapshot(owner: "a", activity: saved)
        XCTAssertEqual(try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        XCTAssertNil(snapshot.scoped(to: "b").activity)
        XCTAssertNil(saved.loads[dates[0]])
    }

    func testDisplayedStepsPreferFilteredDetailThenFilteredSummary() throws {
        let day = "2026-01-03"
        let summary = try JSONDecoder().decode(ZoopAPI.Day.self, from: Data(
            #"{"day":"2026-01-03","steps":12000,"stepsWalking":7800,"samples":12}"#.utf8))
        func details(_ walking: Int) -> ZoopAPI.StepsDay {
            .init(day: day, hours: [], walkingHours: [], total: 12000, walking: walking, bouts: [])
        }
        XCTAssertEqual(ZoopAPI.StepsDay.displayedCount(on: day, details: details(8000), summary: summary), 8000)
        XCTAssertEqual(ZoopAPI.StepsDay.displayedCount(on: day, details: nil, summary: summary), 7800)
        XCTAssertEqual(ZoopAPI.StepsDay.displayedCount(on: day, details: details(0), summary: summary), 0)
        XCTAssertNil(ZoopAPI.StepsDay.displayedCount(on: day, details: details(0), summary: nil))
        XCTAssertNil(ZoopAPI.StepsDay.displayedCount(on: "2026-01-04", details: details(8000), summary: summary))
    }
}
