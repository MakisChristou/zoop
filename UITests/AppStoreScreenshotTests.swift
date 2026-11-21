import XCTest

/// Actual Release UI with generated, loopback-only data. No personal recordings.
@MainActor final class AppStoreScreenshotTests: XCTestCase {
    func testStoreScreenshots() {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "DESIGN-SLEEP-STORE",
            "-serverURL", "http://127.0.0.1:28476", "-ingestToken", "ui-test-token",
            "-onboarded", "YES", "-demoScreen", "today", "-sleepGoalMinutes", "480",
            "-weightUnit", "kg", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let ring = app.buttons["openRecoverySummary"]
        XCTAssertTrue(ring.waitForExistence(timeout: 20))
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "75"), object: ring)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 20), .completed)
        shot(app, "01-Today")
        ring.tap()
        XCTAssertTrue(app.otherElements["recoveryHistoryChart"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["recoveryPeriod"].waitForExistence(timeout: 10))
        shot(app, "02-Recovery")
        app.navigationBars["Recovery"].buttons.element(boundBy: 0).tap()
        app.buttons["tab-Sleep"].tap()
        XCTAssertTrue(app.buttons["sleepTimelineDetails"].waitForExistence(timeout: 20))
        shot(app, "03-Sleep")
        app.buttons["tab-Activity"].tap()
        XCTAssertTrue(app.buttons["workout-900"].waitForExistence(timeout: 20))
        shot(app, "04-Activity")
        app.buttons["tab-Today"].tap()
        let weight = app.buttons["todayWeight"].firstMatch
        for _ in 0..<10 where !weight.isHittable { app.swipeUp() }
        XCTAssertTrue(weight.isHittable)
        weight.tap()
        XCTAssertTrue(app.otherElements["weightChart"].waitForExistence(timeout: 20))
        shot(app, "05-Weight")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
