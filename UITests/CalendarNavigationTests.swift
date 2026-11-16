import XCTest

@MainActor final class CalendarNavigationTests: XCTestCase {
    private func launch(screen: String = "trends", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "UI-REVIEW", "-serverURL", "http://127.0.0.1:28476", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", screen]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch(); return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, down: Bool = false) {
        XCTAssertTrue(element.waitForExistence(timeout: 20))
        for _ in 0..<16 where !element.isHittable {
            let above = element.frame.maxY < app.frame.midY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: above || down ? 0.4 : 0.75))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: above || down ? 0.75 : 0.4))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable)
    }
    func testMonthPagingInspectionAndReturnKeepThePeriod() {
        let app = launch(), chart = app.otherElements["trendsChart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 20))
        let month = app.staticTexts["trendPeriod"].label
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).press(forDuration: 0.05, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        XCTAssertNotEqual(app.staticTexts["trendPeriod"].label, month)
        XCTAssertFalse(app.buttons["trendLatest"].exists)
        let previous = app.staticTexts["trendPeriod"].label
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(forDuration: 0.3, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)))
        XCTAssertEqual(app.staticTexts["trendPeriod"].label, previous)
        XCTAssertTrue(app.buttons["trendOpenDetail"].exists)
        let reading = chart.value as? String
        shot(app, "Calendar month inspection")
        app.buttons["trendOpenDetail"].tap()
        XCTAssertTrue(app.buttons["Sleep options"].waitForExistence(timeout: 15))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        XCTAssertEqual(chart.value as? String, reading)
        XCTAssertEqual(app.staticTexts["trendPeriod"].label, previous)
        app.buttons["trendNextPeriod"].tap()
        XCTAssertEqual(app.staticTexts["trendPeriod"].label, month)
        XCTAssertFalse(app.buttons["trendNextPeriod"].isEnabled)
    }
    func testHeatmapSheetOpensTheRecordedSleep() {
        let app = launch()
        XCTAssertTrue(app.otherElements["trendsChart"].waitForExistence(timeout: 20))
        let cells = app.buttons.matching(identifier: "sleepHeatmapDay")
        let cell = cells.element(boundBy: 35)
        reveal(cell, in: app)
        XCTAssertTrue(cell.isEnabled); cell.tap()
        XCTAssertTrue(app.buttons["heatmapOpenSleep"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Efficiency"].exists)
        shot(app, "Sleep heatmap detail sheet")
        app.buttons["heatmapOpenSleep"].tap()
        XCTAssertTrue(app.buttons["Sleep options"].waitForExistence(timeout: 15))
        shot(app, "Heatmap to full sleep")
    }
    func testTodayCirclesAndFourTabsWithBatteryInProfile() {
        let app = launch(screen: "")
        XCTAssertTrue(app.otherElements["weightWeekCircles"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.tabBars.buttons.count, 5)
        XCTAssertFalse(app.tabBars.buttons["Battery"].exists)
        XCTAssertTrue(app.buttons["openMorningInsights"].waitForExistence(timeout: 20))
        shot(app, "Today restored check-ins")
        app.buttons["openDeviceShortcut"].tap()
        XCTAssertTrue(app.navigationBars["My WHOOP"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Battery pack"].exists)
        shot(app, "Batteries in My WHOOP")
        app.buttons["Close"].tap()
        let chart = app.descendants(matching: .any)["todayHeartRateChart"].firstMatch
        reveal(chart, in: app); shot(app, "Live reading in timeline")
    }
    func testBatteryNotificationDestination() {
        let app = launch(screen: "battery")
        XCTAssertTrue(app.navigationBars["My WHOOP"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Battery pack"].exists)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].exists)
    }
    func testMorningSharesCalendarChartAndMetricSelection() {
        let app = launch(screen: "")
        let brief = app.buttons["openMorningInsights"]
        reveal(brief, in: app); brief.tap()
        XCTAssertTrue(app.otherElements["trendsChart"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.otherElements.matching(identifier: "trendsChart").count, 1)
        XCTAssertTrue(app.segmentedControls.buttons["Week"].isSelected)
        app.buttons["insightMetric_hrv"].tap()
        XCTAssertTrue(app.otherElements["trendsChart"].label.contains("HRV"))
        app.segmentedControls.buttons["Week"].tap()
        let period = app.staticTexts["trendPeriod"].label
        app.buttons["trendPreviousPeriod"].tap()
        XCTAssertNotEqual(app.staticTexts["trendPeriod"].label, period)
        shot(app, "Morning shared calendar chart")
    }
    func testLargeTextCalendarAndHeatmapDetailsRemainReachable() {
        let app = launch(large: true), chart = app.otherElements["trendsChart"]
        reveal(chart, in: app)
        shot(app, "Calendar chart largest text")
        let cell = app.buttons.matching(identifier: "sleepHeatmapDay").element(boundBy: 35)
        reveal(cell, in: app); cell.tap()
        let detail = app.buttons["heatmapOpenSleep"]
        reveal(detail, in: app)
        shot(app, "Heatmap detail largest text")
        XCTAssertTrue(app.buttons["Done"].isHittable)
    }
    func testSleepShowsCompactPersonalComparisons() {
        let app = launch(screen: "sleep")
        let efficiency = app.staticTexts["Efficiency"]
        reveal(efficiency, in: app)
        let delta = app.staticTexts["1 percentage point above your recent average"]
        XCTAssertTrue(delta.waitForExistence(timeout: 15))
        shot(app, "Sleep personal deltas")
    }
}
