import XCTest

/// Measures the app process, not the UI-test runner. Use the same synthetic history
/// and simulator for before/after comparisons; this is not a physical frame-rate claim.
@MainActor final class TrendRangePerformanceTests: XCTestCase {
    func testRepeatedWeekMonthSwitches() {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "UI-REVIEW", "-serverURL", ProcessInfo.processInfo.environment["SNOOP_UI_SERVER_URL"] ?? "http://127.0.0.1:28476", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", "trends"]
        app.launch()
        XCTAssertTrue(app.otherElements["trendsChart"].waitForExistence(timeout: 20))
        let week = app.segmentedControls.buttons["Week"], month = app.segmentedControls.buttons["Month"]
        week.tap(); month.tap()
        let options = XCTMeasureOptions(); options.iterationCount = 3
        measure(metrics: [XCTCPUMetric(application: app), XCTMemoryMetric(application: app), XCTClockMetric()], options: options) {
            for _ in 0..<3 { week.tap(); month.tap() }
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Range switching month result"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(app.otherElements["trendsChart"].exists)
    }
}
