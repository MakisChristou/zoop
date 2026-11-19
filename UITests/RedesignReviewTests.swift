import XCTest

/// Presentation and navigation regression checks against local generated history.
@MainActor final class RedesignReviewTests: XCTestCase {
    private func launch(_ screen: String = "today", large: Bool = false, weekly: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "DESIGN-" + UUID().uuidString,
            "-serverURL", weekly ? "http://127.0.0.1:28482" : "http://127.0.0.1:28476",
            "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", screen,
            "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 2)
        for _ in 0..<16 where !element.exists || !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    func testMainPagesAndWeightNavigation() {
        let app = launch()
        XCTAssertTrue(app.buttons["tab-Today"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tab-")).count, 5)
        XCTAssertFalse(app.tabBars.firstMatch.exists, "Only the custom navigation is visible")
        XCTAssertFalse(app.staticTexts["morningOutlookStatus"].exists)
        let weight = app.buttons["todayWeight"].firstMatch
        reveal(weight, in: app)
        // Weight sync is independent of the history request.
        let logged = app.staticTexts["Logged"]
        XCTAssertTrue(logged.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["todayLogWeight"].exists)
        shot(app, "01 Today")
        weight.tap()
        XCTAssertTrue(app.otherElements["weightChart"].waitForExistence(timeout: 10))
        shot(app, "02 Weight")
        app.buttons["Weight options"].tap()
        XCTAssertTrue(app.buttons["importWeightFromOptions"].waitForExistence(timeout: 5))
        shot(app, "03 Weight options")
        app.buttons["Done"].tap()
        app.buttons["tab-Activity"].tap()
        XCTAssertTrue(app.staticTexts["Daily load"].waitForExistence(timeout: 10))
        shot(app, "04 Activity")
        app.buttons["tab-Sleep"].tap()
        XCTAssertTrue(app.buttons["Sleep options"].waitForExistence(timeout: 10))
        shot(app, "05 Sleep")
        reveal(app.staticTexts["sleepDelta-Resting heart rate"], in: app)
        shot(app, "06 Sleep metrics")
        app.buttons["tab-Trends"].tap()
        XCTAssertTrue(app.otherElements["trendsChart"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        shot(app, "07 Trends")
        app.segmentedControls.buttons["Week"].tap()
        app.buttons["trendPreviousPeriod"].tap()
        shot(app, "08 Trends previous week")
        app.buttons["tab-Today"].tap()
        XCTAssertTrue(app.navigationBars["Weight"].exists, "Switching tabs preserves the open detail")
    }
    func testGoalsAndProfileFlows() {
        let app = launch("goals", weekly: true)
        XCTAssertTrue(app.otherElements["cutProgress"].waitForExistence(timeout: 15))
        shot(app, "09 Goals")
        app.buttons["cutPreviousWeek"].tap()
        XCTAssertEqual(app.staticTexts["cutSelectedWeek"].label, "Week 3")
        shot(app, "10 Goals previous week")
        app.buttons["cutOptions"].tap(); app.buttons["editWeightGoal"].tap()
        XCTAssertTrue(app.textFields["weeklyLossInput"].waitForExistence(timeout: 5))
        shot(app, "11 Goal setup"); app.buttons["Cancel"].tap()
        app.buttons["openProfile"].tap()
        XCTAssertTrue(app.buttons["openECG"].waitForExistence(timeout: 5))
        shot(app, "12 Profile")
        app.buttons["openECG"].tap()
        XCTAssertTrue(app.buttons["recordECG"].waitForExistence(timeout: 5))
        shot(app, "13 ECG")
    }
    func testLargeTextScreensKeepControlsReachable() {
        let app = launch(large: true)
        XCTAssertTrue(app.buttons["tab-Today"].waitForExistence(timeout: 10))
        shot(app, "14 Today large text")
        reveal(app.buttons["todayWeight"].firstMatch, in: app)
        app.buttons["todayWeight"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["weightChart"].waitForExistence(timeout: 20))
        shot(app, "15 Weight large text")
        app.buttons["tab-Sleep"].tap()
        XCTAssertTrue(app.buttons["Sleep options"].waitForExistence(timeout: 10))
        shot(app, "16 Sleep large text")
        reveal(app.staticTexts["sleepDelta-Resting heart rate"], in: app)
        shot(app, "17 Sleep metrics large text")
        app.buttons["tab-Trends"].tap()
        XCTAssertTrue(app.otherElements["trendsChart"].waitForExistence(timeout: 10))
        shot(app, "18 Trends large text")
    }
}
