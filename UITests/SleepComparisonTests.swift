import XCTest

@MainActor final class SleepComparisonTests: XCTestCase {
    private func capture(large: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "SLEEP-COMPARISON", "-serverURL", "http://127.0.0.1:28476", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", "sleep"]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.buttons["Sleep options"].waitForExistence(timeout: 20))
        for title in ["Time asleep", "Deep", "REM", "Light", "Efficiency", "Awake", "Resting heart rate", "HRV", "Breathing", "SpO₂", "Skin temperature", "Disturbances"] {
            let badge = app.staticTexts["sleepDelta-\(title)"]
            for _ in 0..<12 where !badge.isHittable { app.swipeUp(velocity: .slow) }
            XCTAssertTrue(badge.isHittable, "Comparison reachable: \(title)")
            XCTAssertTrue(badge.label.contains("average"))
            if ["Light", "Resting heart rate", "Skin temperature"].contains(title) {
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "Sleep comparisons \(title) \(large ? "large text" : "standard text")"
                shot.lifetime = .keepAlways
                add(shot)
            }
        }
    }
    func testComparisonsFitSmallPhone() { capture(large: false) }
    func testComparisonsRemainReachableAtLargestText() { capture(large: true) }
}
