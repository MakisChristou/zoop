import XCTest

/// Synthetic INSIGHT-REVIEW only; no physical phone or personal recordings.
@MainActor final class MorningInsightsTests: XCTestCase {
    private func launch(large: Bool = false, state: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", state.map { "MORNING-CARD-" + $0 } ?? "INSIGHT-REVIEW", "-serverURL", ProcessInfo.processInfo.environment["SNOOP_UI_SERVER_URL"] ?? "http://127.0.0.1:28476", "-ingestToken", "ui-test-token", "-onboarded", "YES"]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func open(_ app: XCUIApplication) {
        let brief = app.buttons["openMorningInsights"]
        XCTAssertTrue(brief.waitForExistence(timeout: 25))
        for _ in 0..<14 {
            if brief.isHittable && brief.frame.midY < app.buttons["tab-Today"].frame.minY - 24 { break }
            app.swipeUp()
        }
        brief.tap()
        XCTAssertTrue(app.navigationBars["Morning insights"].waitForExistence(timeout: 10))
    }
    func testBriefDetailsMethodsAndPreviousDay() {
        let app = launch()
        XCTAssertTrue(app.buttons["openMorningInsights"].waitForExistence(timeout: 25))
        XCTAssertFalse(app.staticTexts["morningOutlookStatus"].exists)
        shot(app, "Today neutral headline")
        open(app)
        let comparison = app.buttons["trendComparisons"].firstMatch
        XCTAssertTrue(comparison.waitForExistence(timeout: 15))
        for _ in 0..<12 where !comparison.isHittable || comparison.frame.midY > app.buttons["tab-Today"].frame.minY - 24 { app.swipeUp() }
        comparison.tap()
        XCTAssertTrue(app.staticTexts["Based on 14 nights"].firstMatch.waitForExistence(timeout: 5))
        shot(app, "Morning comparisons")
        app.buttons["About morning insights"].tap()
        XCTAssertTrue(app.navigationBars["About insights"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<14 {
            let previous = app.buttons["Previous day"]
            if previous.isHittable && previous.frame.minY > app.buttons["openProfile"].frame.maxY { break }
            app.swipeDown()
        }
        app.buttons["Previous day"].tap()
        XCTAssertTrue(app.staticTexts["Yesterday"].waitForExistence(timeout: 5))
        open(app)
        XCTAssertTrue(comparison.waitForExistence(timeout: 15))
        for _ in 0..<12 where !comparison.isHittable || comparison.frame.midY > app.buttons["tab-Today"].frame.minY - 24 { app.swipeUp() }
        comparison.tap()
        XCTAssertTrue(app.staticTexts["Early baseline · 13 nights"].firstMatch.waitForExistence(timeout: 15))
        shot(app, "Yesterday early baseline")
    }
    func testLargeTextDetailsRemainReadable() {
        let app = launch(large: true)
        XCTAssertTrue(app.buttons["openMorningInsights"].waitForExistence(timeout: 25))
        shot(app, "Today headline accessibility text")
        open(app)
        XCTAssertTrue(app.staticTexts["morningOutlookStatus"].firstMatch.waitForExistence(timeout: 10))
        shot(app, "Morning insights large text")
        let weekly = app.buttons["trendComparisons"]
        for _ in 0..<8 { if weekly.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(weekly.isHittable); weekly.tap()
        for _ in 0..<4 { if app.staticTexts["Sleep timing"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Sleep timing"].exists)
        shot(app, "Weekly insights large text")
    }
    func testCompactCardStates() {
        for (state, title) in [("average", "Average"), ("good", "Good"), ("low", "Low"), ("learning", "Learning"), ("limited", "Limited data"), ("updating", "Updating"), ("no_sleep", "No sleep")] {
            let app = launch(state: state)
            let card = app.buttons["openMorningInsights"]
            XCTAssertTrue(card.waitForExistence(timeout: 20))
            XCTAssertFalse(app.staticTexts["morningOutlookStatus"].exists)
            open(app)
            if state == "updating" {
                XCTAssertTrue(app.descendants(matching: .any)["morningInsightsLoading"].firstMatch.waitForExistence(timeout: 10))
                XCTAssertFalse(app.staticTexts["Updating"].exists)
            } else {
                let status = app.staticTexts["morningOutlookStatus"].firstMatch
                XCTAssertTrue(status.waitForExistence(timeout: 10))
                XCTAssertEqual(status.label, title)
            }
            XCTAssertFalse(app.staticTexts["Strong"].exists)
            XCTAssertFalse(app.staticTexts["Compared with your usual"].exists)
            shot(app, "Compact morning " + state)
            app.terminate()
        }
    }
    func testMetricSelectionPagingAndChartDetails() {
        let app = launch()
        open(app)
        let sleep = app.buttons["insightMetric_sleep"]
        XCTAssertTrue(sleep.waitForExistence(timeout: 15))
        XCTAssertTrue(sleep.isSelected)
        XCTAssertFalse(app.staticTexts["trendReadingValue"].exists)
        shot(app, "Morning integrated sleep")
        app.buttons["insightMetric_hrv"].tap()
        XCTAssertTrue(app.buttons["insightMetric_hrv"].isSelected)
        XCTAssertEqual(app.otherElements["trendsChart"].label, "HRV trend chart")
        shot(app, "Morning integrated HRV")
        app.buttons["insightMetric_resting_hr"].tap()
        XCTAssertTrue(app.buttons["insightMetric_resting_hr"].isSelected)
        app.segmentedControls.buttons["Month"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Month"].isSelected)
        app.buttons["trendPreviousPeriod"].tap()
        XCTAssertTrue(app.staticTexts["trendReadingValue"].exists)
        app.buttons["trendNextPeriod"].tap()
        XCTAssertFalse(app.staticTexts["trendReadingValue"].exists)
        app.buttons["insightMetric_sleep"].tap()
        let chart = app.otherElements["trendsChart"]
        let chartTop = chart.frame.minY
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["trendOpenDetail"].waitForExistence(timeout: 5))
        XCTAssertEqual(chart.frame.minY, chartTop, accuracy: 1)
        shot(app, "Morning selected reading")
        app.buttons["trendOpenDetail"].tap()
        XCTAssertFalse(app.navigationBars["Morning insights"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["trendOpenDetail"].waitForExistence(timeout: 5))
    }

    func testCompactCardLargeTextAndNavigation() {
        let app = launch(large: true, state: "average")
        let card = app.buttons["openMorningInsights"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        XCTAssertEqual(card.label, "Outlook")
        shot(app, "Compact morning large text top")
        app.swipeUp()
        shot(app, "Compact morning large text comparisons")
        open(app)
    }

}
