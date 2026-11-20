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
    func testReferenceChartPanels() {
        let app = launch("trends")
        let chart = app.otherElements["trendsChart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 15))
        app.buttons["HRV"].tap()
        shot(app, "19 HRV reference")
        app.buttons["Resting HR"].tap()
        shot(app, "20 RHR reference")
        app.buttons["HRV"].tap()
        let original = chart.frame
        chart.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["trendOpenDetail"].waitForExistence(timeout: 5))
        XCTAssertEqual(chart.frame.minY, original.minY, accuracy: 1)
        shot(app, "21 HRV selected")
        app.buttons["trendLatest"].tap()
        XCTAssertFalse(app.buttons["trendOpenDetail"].exists)
        app.buttons["tab-Today"].tap()
        XCTAssertTrue(app.buttons["openSteps"].waitForExistence(timeout: 10))
        shot(app, "22 Today top")
    }
    func testSecondaryChartScreens() {
        let app = launch("sleep")
        let timeline = app.buttons["sleepTimelineDetails"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 15)); timeline.tap()
        XCTAssertTrue(app.staticTexts["Heart rate"].waitForExistence(timeout: 15))
        app.swipeUp()
        shot(app, "23 Sleep signal charts")
        app.buttons["tab-Activity"].tap()
        let workout = app.buttons["workout-900"]
        XCTAssertTrue(workout.waitForExistence(timeout: 15)); workout.tap()
        XCTAssertTrue(app.staticTexts["Heart rate"].waitForExistence(timeout: 10))
        app.swipeUp()
        XCTAssertTrue(NSPredicate(format: "label == %@", "bpm").evaluate(with: app.staticTexts["workoutChartState"]))
        XCTAssertFalse(app.staticTexts["Unused synthetic endpoint"].exists)
        shot(app, "24 Workout chart")
        app.buttons["tab-Today"].tap()
        let steps = app.buttons["openSteps"]
        reveal(steps, in: app); steps.tap()
        XCTAssertTrue(app.staticTexts["By hour"].waitForExistence(timeout: 10))
        shot(app, "25 Steps chart")
        app.buttons["tab-Trends"].tap()
        let progress = app.buttons["openProgress"]
        reveal(progress, in: app); progress.tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 10))
        shot(app, "26 Progress charts")
    }
    func testWeightChartPagingAndInspection() {
        let app = launch()
        let weight = app.buttons["todayWeight"].firstMatch
        reveal(weight, in: app)
        XCTAssertTrue(app.staticTexts["Logged"].waitForExistence(timeout: 15))
        weight.tap()
        let chart = app.otherElements["weightChart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        let current = app.staticTexts["weightChartDates"].label
        app.buttons["weightPreviousPeriod"].tap()
        XCTAssertNotEqual(app.staticTexts["weightChartDates"].label, current)
        chart.coordinate(withNormalizedOffset: .init(dx: 0.8, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: chart.coordinate(withNormalizedOffset: .init(dx: 0.2, dy: 0.5)))
        XCTAssertEqual(app.staticTexts["weightChartDates"].label, current)
        let frame = chart.frame
        chart.coordinate(withNormalizedOffset: .init(dx: 0.2, dy: 0.5))
            .press(forDuration: 0.35, thenDragTo: chart.coordinate(withNormalizedOffset: .init(dx: 0.7, dy: 0.5)))
        XCTAssertEqual(app.staticTexts["weightChartHeadline"].label, "Selected weigh-in")
        XCTAssertEqual(chart.frame.minY, frame.minY, accuracy: 1)
        shot(app, "28 Weight inspection")
        app.buttons["weightChartLatest"].tap()
        XCTAssertFalse(app.buttons["weightChartLatest"].exists)
    }
    func testSleepStagePanelComparison() {
        let app = launch("sleep")
        XCTAssertTrue(app.buttons["Sleep options"].waitForExistence(timeout: 15))
        app.coordinate(withNormalizedOffset: .init(dx: 0.95, dy: 0.70))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.95, dy: 0.47)))
        XCTAssertGreaterThan(app.staticTexts["Sleep stages"].frame.minY, app.buttons["openProfile"].frame.maxY + 10)
        XCTAssertTrue(app.staticTexts["Fell asleep"].isHittable)
        XCTAssertTrue(app.staticTexts["Woke up"].isHittable)
        shot(app, "27 Sleep stages")
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
