import XCTest

@MainActor final class RecoveryHistoryTests: XCTestCase {
    private func launch(_ device: String = "RECOVERY-HISTORY", large: Bool = false, screen: String = "trends") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", device, "-serverURL", "http://127.0.0.1:28476", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", screen, "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        let recovery = app.buttons[screen == "trends" ? "Recovery" : "openRecoverySummary"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 15)); recovery.tap()
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testWaitingForSyncIsNotAnActiveCalculation() {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "RECOVERY-awaiting_sync", "-serverURL", "http://127.0.0.1:28476", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", "today"]
        app.launch()
        let ring = app.buttons["openRecoverySummary"]
        XCTAssertTrue(ring.waitForExistence(timeout: 15))
        let waiting = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "Waiting for sync"), object: ring)
        XCTAssertEqual(XCTWaiter.wait(for: [waiting], timeout: 15), .completed)
        XCTAssertEqual(ring.progressIndicators.count, 0)
        shot(app, "Recovery waiting for sync")
        ring.tap()
        selectToday(app)
        XCTAssertTrue(app.staticTexts["Waiting for sync"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["recoveryScoreLoading"].firstMatch.exists)
        shot(app, "Recovery detail waiting")
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
    func testPendingScoreUsesLoadingIndicatorUntilReady() {
        for screen in ["trends", "today"] {
            let app = launch("RECOVERY-LOADING-" + UUID().uuidString, screen: screen)
            if screen == "today" { selectToday(app) }
            let loading = app.descendants(matching: .any)["recoveryScoreLoading"].firstMatch
            XCTAssertTrue(loading.waitForExistence(timeout: 10))
            XCTAssertTrue(app.otherElements["recoveryHistoryChart"].exists)
            XCTAssertFalse(app.staticTexts["Updating"].exists)
            shot(app, "Recovery loading " + screen)
            let score = app.staticTexts["recoveryHistoryScore"]
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "75%"), object: score)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
            XCTAssertFalse(loading.exists)
            shot(app, "Recovery ready " + screen)
            app.terminate()
        }
    }
    private func selectToday(_ app: XCUIApplication) {
        let chart = app.otherElements["recoveryHistoryChart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 15))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(), day = calendar.component(.day, from: date)
        let days = calendar.range(of: .day, in: .month, for: date)!.count
        // The chart's leading labels occupy about 36 points; the remainder is the plot.
        let x = 36 + (chart.frame.width - 36) * (Double(day) - 0.5) / Double(days)
        chart.coordinate(withNormalizedOffset: .zero).withOffset(.init(dx: x, dy: 60)).tap()
    }
    func testDetailStartsQuietAndRevealsSelectedReadings() {
        let app = launch(screen: "today")
        let chart = app.otherElements["recoveryHistoryChart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["recoverySelectedDate"].exists)
        XCTAssertFalse(app.staticTexts["recoveryHistoryScore"].exists)
        XCTAssertFalse(app.buttons["Clear recovery selection"].exists)
        shot(app, "Recovery quiet overview")
        selectToday(app)
        XCTAssertTrue(app.staticTexts["recoveryHistoryScore"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["recoveryHistoryScore"].label, "75%")
        shot(app, "Recovery selected readings")
        app.buttons["Clear recovery selection"].tap()
        XCTAssertFalse(app.staticTexts["recoverySelectedDate"].exists)
        selectToday(app)
        app.segmentedControls["recoveryRange"].buttons["Week"].tap()
        XCTAssertFalse(app.staticTexts["recoverySelectedDate"].exists)
        chart.coordinate(withNormalizedOffset: .init(dx: 0.3, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["recoverySelectedDate"].exists)
        app.buttons["Previous recovery period"].tap()
        XCTAssertFalse(app.staticTexts["recoverySelectedDate"].exists)
        chart.swipeRight()
        XCTAssertFalse(app.staticTexts["recoverySelectedDate"].exists)
        for range in ["3 months", "Year", "Month"] {
            app.segmentedControls["recoveryRange"].buttons[range].tap()
            XCTAssertTrue(chart.exists)
            XCTAssertFalse(app.staticTexts["recoverySelectedDate"].exists)
        }
    }
    func testDetailLargeTextOverviewAndSelection() {
        let app = launch(large: true, screen: "today")
        XCTAssertTrue(app.otherElements["recoveryHistoryChart"].waitForExistence(timeout: 15))
        shot(app, "Recovery quiet large text")
        selectToday(app)
        XCTAssertTrue(app.staticTexts["recoveryHistoryScore"].exists)
        app.swipeUp()
        shot(app, "Recovery selection large text")
        let clear = app.buttons["Clear recovery selection"]
        for _ in 0..<3 where !clear.isHittable { app.swipeDown() }
        XCTAssertTrue(clear.isHittable); clear.tap()
        XCTAssertFalse(app.staticTexts["recoverySelectedDate"].exists)
    }
    func testLargeText() {
        let app = launch(large: true)
        XCTAssertTrue(app.staticTexts["recoveryStatus"].waitForExistence(timeout: 15))
        shot(app, "Recovery large text")
        app.swipeUp()
        shot(app, "Recovery large text readings")
    }
}
