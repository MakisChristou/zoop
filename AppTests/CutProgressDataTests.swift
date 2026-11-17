import XCTest
@testable import Snoop

final class CutProgressDataTests: XCTestCase {
    private let calendar = CutPlan.calendar(timezone: "Europe/Berlin")
    private func date(_ key: String) -> Date { CutPlan.date(key, calendar: calendar)! }
    private func data(started: String = "2026-03-23", now: String = "2026-03-30", finish: String? = "2026-04-06", loss: Double? = 0.5, target: Double? = 69, pace: String? = nil, weeks: [SnoopAPI.WeightWeek] = [], readings: [SnoopAPI.CutWeighIn]? = nil) -> CutProgressData {
        let goal = SnoopAPI.WeightGoal(revision: 1, active: true, startedAt: date(started), paceStartedAt: date(pace ?? started), timezone: "Europe/Berlin", weeklyLossKg: 0.5, reminderEnabled: false, reminderWeekday: 1, reminderMinute: 1200, finishDate: finish, updatedAt: date(now))
        let summary = SnoopAPI.WeeklyWeightSummary(algorithmVersion: 1, start: "2026-03-30", end: "2026-04-05", provisional: true, state: "starting", reason: "first_week", medianKg: 69.5, changeKg: nil, weeklyLossKg: 0.5, count: 1, weekNumber: 2, weeks: weeks, progress: .init(finishDate: finish, weeksRemaining: 1, completed: false, startingWeightKg: 70, currentWeightKg: loss.map { 70 - $0 }, totalLostKg: loss, targetWeightKg: target, weighIns: readings))
        return CutProgressData(goal: goal, summary: summary, now: date(now))
    }
    private func week(_ start: String, _ end: String, _ median: Double?, eligible: Bool = true) -> SnoopAPI.WeightWeek {
        .init(start: start, end: end, medianKg: median, count: median == nil ? 0 : 6, eligible: eligible)
    }
    func testCalendarDaysCrossDSTWithoutLosingADay() throws {
        let d = data(), time = try XCTUnwrap(d.time)
        XCTAssertEqual(time.elapsed, 7); XCTAssertEqual(time.total, 14); XCTAssertEqual(time.remaining, 7)
        XCTAssertEqual(time.fraction, 0.5); XCTAssertEqual(d.weightFraction, 0.5)
    }
    func testFinishAndFutureStartClampTimeWithoutNegativeProgress() {
        XCTAssertEqual(data(now: "2026-03-22").time?.elapsed, 0)
        XCTAssertEqual(data(now: "2026-04-06").time?.remaining, 0)
        XCTAssertFalse(data(now: "2026-04-06").completed)
        XCTAssertTrue(data(now: "2026-04-07").completed)
        XCTAssertEqual(data(now: "2026-04-07").time?.fraction, 1)
    }
    func testOpenEndedAndInvalidDatesDoNotInventTimeOrTargetPath() {
        XCTAssertNil(data(finish: nil).time); XCTAssertTrue(data(finish: nil).targetPath.isEmpty)
        XCTAssertNil(data(finish: "2026-03-23").time)
        XCTAssertTrue(data(finish: "2026-03-23").targetPath.isEmpty)
    }
    func testWeightGainOvershootAndMissingBaselineStayHonest() {
        XCTAssertEqual(data(loss: -0.7).weightFraction, 0)
        XCTAssertEqual(data(loss: 2).weightFraction, 1)
        XCTAssertNil(data(loss: nil).weightFraction)
        XCTAssertNil(data(target: nil).weightFraction)
        XCTAssertNil(data(target: 71).weightFraction)
    }
    func testTargetPathIsNotRetroactivelyAppliedAfterPaceChange() {
        XCTAssertEqual(data().targetPath.count, 2)
        XCTAssertEqual(data().targetPath.first?.kg, 70)
        XCTAssertEqual(data().targetPath.last?.kg, 69)
        XCTAssertTrue(data(pace: "2026-03-24").targetPath.isEmpty)
    }
    func testPreCutWeeksAreExcludedAndCurrentWeekIsAddedOnlyOnce() {
        let rows = [week("2026-03-16", "2026-03-22", 71), week("2026-03-23", "2026-03-29", 70), week("2026-03-30", "2026-04-05", 69.5, eligible: false)]
        let d = data(weeks: rows)
        XCTAssertEqual(d.weeks.count, 2)
        XCTAssertEqual(d.number(d.weeks[0]), 1); XCTAssertEqual(d.number(d.weeks[1]), 2)
        XCTAssertTrue(d.points.isEmpty, "Weekly medians must not become daily readings")
        XCTAssertEqual(data(weeks: Array(rows.dropLast())).weeks.count, 2)
    }
    func testSparseWeeksCannotInventDailyReadingsOrComparisons() {
        let rows = [week("2026-03-23", "2026-03-29", 70), week("2026-03-30", "2026-04-05", nil), week("2026-04-06", "2026-04-12", 69)]
        let d = data(now: "2026-04-13", finish: nil, weeks: rows)
        XCTAssertTrue(d.points.isEmpty)
        XCTAssertNil(d.change(d.weeks.last!))
    }
    func testMidweekStartHasDistinctCalendarWeekNumbers() {
        let rows = [week("2026-03-23", "2026-03-29", 70, eligible: false), week("2026-03-30", "2026-04-05", 69.5)]
        let d = data(started: "2026-03-25", weeks: rows)
        XCTAssertEqual(d.number(d.weeks[0]), 1)
        XCTAssertEqual(d.number(d.weeks[1]), 2)
        XCTAssertEqual(d.time?.elapsed, 5)
    }
    func testHistoricalChangesRequireAdjacentEligibleWeeks() {
        let rows = [week("2026-03-23", "2026-03-29", 70), week("2026-03-30", "2026-04-05", 69.5), week("2026-04-06", "2026-04-12", 69.1)]
        let d = data(now: "2026-04-13", finish: nil, weeks: rows)
        XCTAssertEqual(d.change(d.weeks.last!)!, -0.4, accuracy: 0.00001)
        XCTAssertNil(d.change(d.weeks[1]), "The latest summary's unknown change must remain unknown")
    }
    func testDailyChartKeepsTwoReadingsInOneWeekWithoutReplacingThemWithMedian() {
        let d = data(now: "2026-03-24", readings: [.init(day: "2026-03-23", kg: 70.6), .init(day: "2026-03-24", kg: 69.9)])
        XCTAssertEqual(d.points.map(\.kg), [70.6, 69.9])
        XCTAssertEqual(Set(d.points.map(\.id)).count, 2)
        XCTAssertEqual(d.points[0].weekID, d.points[1].weekID)
        XCTAssertEqual(d.points.map(\.date), [date("2026-03-23"), date("2026-03-24")])
    }
    func testDailyChartSortsAndExcludesOutOfCutFutureInvalidAndDuplicateReadings() {
        let d = data(readings: [.init(day: "2026-03-30", kg: 69), .init(day: "2026-03-22", kg: 71),
            .init(day: "2026-03-24", kg: 70), .init(day: "2026-03-24", kg: 90),
            .init(day: "2026-03-31", kg: 68), .init(day: "2026-03-25", kg: .nan)])
        XCTAssertEqual(d.points.map(\.kg), [70, 69])
        XCTAssertEqual(d.points.map(\.date), [date("2026-03-24"), date("2026-03-30")])
    }

}
