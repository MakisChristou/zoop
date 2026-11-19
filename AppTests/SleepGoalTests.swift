import XCTest
@testable import Zoop

final class SleepGoalTests: XCTestCase {
    func testUnderAtAndOverGoalKeepProgressBounded() {
        let goal = SleepGoal(minutes: 480)
        XCTAssertEqual(goal.progress(asleepSeconds: 6 * 3600), 0.75)
        XCTAssertEqual(goal.progress(asleepSeconds: 8 * 3600), 1)
        XCTAssertEqual(goal.progress(asleepSeconds: 10 * 3600), 1)
        XCTAssertEqual(goal.progress(asleepSeconds: nil), 0)
        XCTAssertEqual(goal.progress(asleepSeconds: 0), 0)
        XCTAssertEqual(goal.progress(asleepSeconds: -1), 0)
    }
    func testQuarterHourTargetUsesMinutesWithoutRoundingSleep() {
        let goal = SleepGoal(minutes: 495)
        XCTAssertEqual(goal.progress(asleepSeconds: 7 * 3600 + 25 * 60), 445.0 / 495, accuracy: 0.000001)
        XCTAssertEqual(goal.title, "8h 15m")
        XCTAssertEqual(SleepGoal(minutes: 480).title, "8h")
    }
    func testInvalidStoredGoalFallsBackToEightHours() {
        for invalid in [0, -60, 1, 481, Int.max] {
            let goal = SleepGoal(minutes: invalid)
            XCTAssertEqual(goal.minutes, 480)
            XCTAssertEqual(goal.progress(asleepSeconds: 6 * 3600), 0.75)
        }
    }
}
