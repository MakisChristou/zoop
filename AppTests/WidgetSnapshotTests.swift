import XCTest
@testable import Zoop

final class WidgetSnapshotTests: XCTestCase {
    func testSwitchingScopeDropsAllPreviousReadings() {
        let saved = WidgetSnapshot(owner: "a", sleepSeconds: 5400, load: 12,
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
}
