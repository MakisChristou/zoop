import XCTest

@MainActor final class DayTimelineUITests: XCTestCase {
    private func open(large: Bool = false, device: String = "DESIGN-DAY-REVIEW") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", device, "-serverURL", "http://127.0.0.1:28476", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", "",
                               "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.buttons["openSleepSummary"].waitForExistence(timeout: 20))
        let picker = app.buttons["timelineMetricPicker"]
        for _ in 0..<10 where !picker.exists || !picker.isHittable { app.swipeUp() }
        XCTAssertTrue(picker.exists)
        if !large {
            let distance = picker.frame.midY - 200
            if distance > 20 {
                app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 30, dy: picker.frame.midY))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 30, dy: 200)), withVelocity: .slow, thenHoldForDuration: 0.5)
            }
        }
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func select(_ title: String, in app: XCUIApplication) {
        app.buttons["timelineMetricPicker"].tap()
        let key = title == "Heart rate" ? "heartRate" : title == "Steps" ? "steps" : "temperature"
        app.buttons["timelineMetric-" + key].tap()
        XCTAssertEqual(app.buttons["timelineMetricPicker"].value as? String, title)
    }
    func testMetricMenuSelectionAndVerticalScrolling() {
        let app = open(), chart = app.otherElements["todayTimelineChart"]
        XCTAssertTrue(chart.exists)
        shot(app, "Daily timeline approved heart rate")
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.45)).tap()
        XCTAssertTrue(app.buttons["Return to latest reading"].waitForExistence(timeout: 3))
        shot(app, "Daily timeline selected reading")
        app.buttons["Return to latest reading"].tap()
        select("Steps", in: app); shot(app, "Daily timeline filtered steps")
        XCTAssertFalse(app.buttons["Return to latest reading"].exists)
        select("Temperature", in: app); shot(app, "Daily timeline temperature")
        select("Heart rate", in: app)
        let before = chart.frame.minY
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.05, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.75)))
        XCTAssertLessThan(chart.frame.minY, before - 20)
        XCTAssertFalse(app.buttons["Return to latest reading"].exists)
    }
    func testLargeTextMetricPickerAndEmptyTemperature() {
        let app = open(large: true, device: "DESIGN-DAY-NOTEMP")
        select("Temperature", in: app)
        XCTAssertEqual(app.otherElements["todayTimelineChart"].value as? String, "No reading")
        shot(app, "Daily timeline large text no temperature")
        select("Steps", in: app)
        XCTAssertNotEqual(app.otherElements["todayTimelineChart"].value as? String, "No reading")
    }
}
