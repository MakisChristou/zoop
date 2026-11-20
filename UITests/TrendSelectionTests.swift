import XCTest

/// Synthetic history only. Exercises gestures in the real scroll view and navigation stack.
@MainActor final class TrendSelectionTests: XCTestCase {
    private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "UI-REVIEW", "-serverURL", ProcessInfo.processInfo.environment["SNOOP_UI_SERVER_URL"] ?? "http://127.0.0.1:28476", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", "trends"]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.otherElements["trendsChart"].waitForExistence(timeout: 20))
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testSelectSleepOpenDetailsReturnAndReset() {
        let app = launch(), chart = app.otherElements["trendsChart"]
        let originalDate = app.staticTexts["trendReadingDate"].label, originalFrame = chart.frame
        shot(app, "Trends unchanged appearance")
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["trendOpenDetail"].waitForExistence(timeout: 3))
        let selected = chart.value as? String
        XCTAssertFalse((chart.value as? String ?? "").contains(originalDate))
        XCTAssertEqual(chart.frame.minY, originalFrame.minY, accuracy: 1, "Selection must not move the chart")
        shot(app, "Sleep reading selected")
        app.buttons["trendOpenDetail"].tap()
        XCTAssertTrue(app.buttons["Sleep options"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Time asleep"].exists)
        shot(app, "Selected sleep detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        XCTAssertEqual(chart.value as? String, selected)
        app.buttons["trendLatest"].tap()
        XCTAssertEqual(app.staticTexts["trendReadingDate"].label, originalDate)
        chart.tap()
        app.segmentedControls.buttons["Week"].tap()
        XCTAssertFalse(app.buttons["trendLatest"].exists)
        chart.tap()
        app.buttons["HRV"].tap()
        XCTAssertFalse(app.buttons["trendLatest"].exists)
    }
    func testScrubStepsAndOpenSelectedDay() {
        let app = launch()
        app.buttons["HRV"].swipeLeft()
        let steps = app.buttons["Steps"]
        XCTAssertTrue(steps.waitForExistence(timeout: 5)); steps.tap()
        let chart = app.otherElements["trendsChart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        app.buttons["trendPreviousPeriod"].tap()
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        let earlier = chart.value as? String
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.3, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        XCTAssertNotEqual(chart.value as? String, earlier)
        XCTAssertTrue(app.buttons["trendOpenDetail"].exists)
        shot(app, "Steps reading selected")
        app.buttons["trendOpenDetail"].tap()
        XCTAssertTrue(app.staticTexts["By hour"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.navigationBars["Steps"].exists)
        XCTAssertFalse(app.staticTexts["Couldn’t update steps"].exists)
        shot(app, "Selected steps detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["trendLatest"].waitForExistence(timeout: 5))
    }
    func testLargeTextSelectionAndResetStayReachable() {
        let app = launch(large: true), chart = app.otherElements["trendsChart"]
        // isHittable is true even when only the chart's edge is visible.
        // Bring the actual inspection point above the fixed navigation before tapping.
        for _ in 0..<8 where chart.frame.midY > app.buttons["tab-Trends"].frame.minY - 24 { app.swipeUp() }
        XCTAssertTrue(chart.isHittable)
        XCTAssertLessThan(chart.frame.midY, app.buttons["tab-Trends"].frame.minY)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["trendOpenDetail"].waitForExistence(timeout: 5))
        for _ in 0..<3 where !app.buttons["trendOpenDetail"].isHittable { app.swipeDown() }
        XCTAssertTrue(app.buttons["trendOpenDetail"].isHittable)
        // At the largest text size, the readout and reset can occupy separate viewports.
        let latest = app.buttons["trendLatest"]
        for _ in 0..<12 {
            let top = app.buttons["openProfile"].frame.maxY + 12
            let bottom = app.buttons["tab-Trends"].frame.minY - 12
            if latest.isHittable && latest.frame.midY > top && latest.frame.midY < bottom { break }
            let moveUp = latest.frame.midY > bottom
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: moveUp ? 0.7 : 0.3))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: moveUp ? 0.3 : 0.7)))
        }
        XCTAssertTrue(app.buttons["trendLatest"].isHittable)
        shot(app, "Selected reading at largest text size")
        app.buttons["trendLatest"].tap()
        XCTAssertFalse(app.buttons["trendOpenDetail"].exists)
    }
    func testVerticalSwipeOverChartStillScrollsWithoutSelecting() {
        let app = launch(), chart = app.otherElements["trendsChart"]
        let before = chart.frame.minY
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(forDuration: 0.05, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.8)))
        XCTAssertLessThan(chart.frame.minY, before - 20)
        XCTAssertFalse(app.buttons["trendLatest"].exists)
        shot(app, "Vertical scroll starting on chart")
    }
}
