import XCTest
import UserNotifications
@testable import Snoop

@MainActor final class NotificationResponseTests: XCTestCase {
    func testBackgroundResponseRoutesBeforeCompletingOnMainThread() async {
        let name = "NotificationResponseTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let center = UNUserNotificationCenter.current()
        let oldDelegate = center.delegate
        defer { center.delegate = oldDelegate }
        let monitor = BatteryMonitor(defaults: defaults, center: center)
        for destination in ["ecg", "weight", "weeklyWeight", "steps", "battery", "workout", "unknown"] {
            let done = expectation(description: "Complete \(destination) on main")
            done.assertForOverFulfill = true
            await Task.detached {
                XCTAssertFalse(Thread.isMainThread)
                monitor.finishNotificationResponse(destination: destination, scope: "test-scope", id: 42) {
                    XCTAssertTrue(Thread.isMainThread)
                    MainActor.assumeIsolated {
                        switch destination {
                        case "ecg": XCTAssertEqual(monitor.openECGScope, "test-scope")
                        case "weight": XCTAssertEqual(monitor.openWeightScope, "test-scope")
                        case "weeklyWeight": XCTAssertEqual(monitor.openWeeklyWeightScope, "test-scope")
                        case "steps": XCTAssertEqual(monitor.openStepsScope, "test-scope")
                        case "battery": XCTAssertTrue(monitor.openBattery)
                        case "workout": XCTAssertEqual(monitor.openWorkout, 42)
                        default: break
                        }
                    }
                    done.fulfill()
                }
            }.value
            await fulfillment(of: [done], timeout: 3)
        }
    }
}
