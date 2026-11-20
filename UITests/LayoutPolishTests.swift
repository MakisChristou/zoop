import XCTest

/// Generated history from tools/layout-test-server.py; never uses a real account.
@MainActor final class LayoutPolishTests: XCTestCase {
    private func launch(screen: String = "", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "UI-REVIEW", "-serverURL", "http://127.0.0.1:28476", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", screen, "-weightUnit", "kg"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 20))
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    func testWeightVerticalScrollDoesNotPageOrSelect() {
        let app = launch(), card = app.buttons["todayWeight"].firstMatch
        reveal(card, in: app); shot(app, "Compact Today and Learning"); card.tap()
        let chart = app.descendants(matching: .any)["Weight chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 15))
        let date = app.staticTexts["weightChartDates"].label
        let before = chart.frame.minY
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(forDuration: 0.05, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.8)))
        XCTAssertLessThan(chart.frame.minY, before - 20)
        XCTAssertEqual(app.staticTexts["weightChartDates"].label, date)
        XCTAssertFalse(app.buttons["weightChartLatest"].exists)
        shot(app, "Weight plot yields to vertical scrolling")
    }
    func testTimelineVerticalScrollDoesNotScrub() {
        let app = launch(), chart = app.descendants(matching: .any)["todayTimelineChart"].firstMatch
        reveal(chart, in: app)
        let before = chart.frame.minY
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).press(forDuration: 0.05, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.5)))
        XCTAssertGreaterThan(chart.frame.minY, before + 20)
        shot(app, "Timeline vertical scroll")
    }
    func testTrendsDisclosuresHeatmapAndShortRange() {
        let app = launch(screen: "trends")
        let chart = app.otherElements["trendsChart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 20))
        shot(app, "Simplified Trends")
        let comparison = app.buttons["trendComparisons"].firstMatch
        XCTAssertTrue(comparison.exists); comparison.tap()
        XCTAssertTrue(app.staticTexts["7-day average"].exists)
        comparison.tap()
        app.segmentedControls.buttons["Week"].tap()
        XCTAssertFalse(app.buttons["weekdayLongerRange"].exists)
        let cells = app.buttons.matching(identifier: "sleepHeatmapDay")
        for _ in 0..<4 where !cells.element(boundBy: 35).isHittable { app.swipeUp() }
        XCTAssertGreaterThan(cells.count, 40)
        XCTAssertTrue(cells.allElementsBoundByIndex.contains { ($0.value as? String ?? "").contains("asleep") })
        shot(app, "Interactive sleep heatmap")
    }
    func testLearningDetailKeepsComparisonsAvailable() {
        let app = launch()
        let brief = app.buttons["openMorningInsights"]
        reveal(brief, in: app)
        XCTAssertFalse(app.staticTexts["Learning"].exists)
        XCTAssertFalse(app.staticTexts["Early comparisons"].exists)
        brief.tap()
        let detail = app.buttons["trendComparisons"].firstMatch
        reveal(detail, in: app)
        XCTAssertFalse(app.staticTexts["Early baseline · 11 nights"].exists)
        detail.tap()
        XCTAssertTrue(app.staticTexts["Early baseline · 11 nights"].exists)
        shot(app, "Morning detail with optional comparisons")
    }
    func testDateHeadingIsCenteredAndResetDoesNotMoveTheControls() {
        let app = launch(), previous = app.buttons["Previous day"]
        XCTAssertTrue(previous.waitForExistence(timeout: 20))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: previous)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
        let title = app.staticTexts["dayNavigationTitle"]
        XCTAssertEqual(title.frame.midX, app.frame.midX, accuracy: 2)
        let top = previous.frame.minY
        previous.tap()
        let reset = app.buttons["Back to today"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        XCTAssertEqual(title.frame.midX, app.frame.midX, accuracy: 2)
        XCTAssertEqual(previous.frame.minY, top, accuracy: 1)
        shot(app, "Centered history heading")
        reset.tap()
        XCTAssertEqual(previous.frame.minY, top, accuracy: 1)
    }
}
