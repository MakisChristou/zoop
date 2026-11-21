import XCTest

@MainActor final class RecoveryHistoryTests: XCTestCase {
    private func launch(_ device: String = "RECOVERY-HISTORY", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", device, "-serverURL", "http://127.0.0.1:28476", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", "trends", "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        let recovery = app.buttons["Recovery"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 15)); recovery.tap()
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testSelectionCalendarPagingAndRanges() {
        let app = launch()
        let chart = app.otherElements["recoveryHistoryChart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["recoveryHistoryScore"].label, "75%")
        shot(app, "Recovery month")
        app.segmentedControls["recoveryRange"].buttons["Week"].tap()
        let date = app.staticTexts["recoverySelectedDate"].label
        chart.coordinate(withNormalizedOffset: .init(dx: 0.3, dy: 0.5)).tap()
        XCTAssertNotEqual(app.staticTexts["recoverySelectedDate"].label, date)
        let period = app.staticTexts["recoveryPeriod"].label
        app.buttons["Previous recovery period"].tap()
        XCTAssertNotEqual(app.staticTexts["recoveryPeriod"].label, period)
        app.buttons["Next recovery period"].tap()
        XCTAssertEqual(app.staticTexts["recoveryPeriod"].label, period)
        chart.swipeRight()
        XCTAssertNotEqual(app.staticTexts["recoveryPeriod"].label, period)
        chart.swipeLeft()
        XCTAssertEqual(app.staticTexts["recoveryPeriod"].label, period)
        for range in ["3 months", "Year", "Month"] {
            app.segmentedControls["recoveryRange"].buttons[range].tap()
            XCTAssertTrue(chart.exists)
        }
        shot(app, "Recovery selected day")
    }
    func testEmptyAndFailure() {
        var app = launch("RECOVERY-HISTORY-EMPTY")
        XCTAssertTrue(app.staticTexts["recoveryStatus"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["recoveryHistoryScore"].label, "—")
        shot(app, "Recovery empty"); app.terminate()
        app = launch("RECOVERY-HISTORY-FAIL")
        XCTAssertTrue(app.buttons["retryRecoveryHistory"].waitForExistence(timeout: 15))
        app.buttons["retryRecoveryHistory"].tap()
        XCTAssertFalse(app.staticTexts["recoveryHistoryScore"].exists)
        shot(app, "Recovery retry")
    }
    func testLargeText() {
        let app = launch(large: true)
        XCTAssertTrue(app.staticTexts["recoveryStatus"].waitForExistence(timeout: 15))
        shot(app, "Recovery large text")
        app.swipeUp()
        shot(app, "Recovery large text readings")
    }
}
