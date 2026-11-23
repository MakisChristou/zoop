import XCTest

@MainActor final class ActivityTimelineTests: XCTestCase {
    private func launch(large: Bool = false, empty: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "DESIGN-TIMELINE-" + (empty ? "EMPTY-" : "") + UUID().uuidString,
            "-serverURL", "http://127.0.0.1:28476", "-ingestToken", "ui-test-token", "-onboarded", "YES",
            "-demoScreen", "activity", "-UIPreferredContentSizeCategoryName",
            large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchSynthetic()
        XCTAssertTrue(app.staticTexts["Recent activities"].waitForExistence(timeout: 15))
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name
        image.lifetime = .keepAlways; add(image)
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<12 {
            if element.isHittable && element.frame.midY < app.buttons["tab-Activity"].frame.minY - 20 { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
    func testTimelineGroupingAndDetailNavigation() {
        let app = launch()
        XCTAssertTrue(app.buttons["workout-900"].waitForExistence(timeout: 15))
        app.coordinate(withNormalizedOffset: .init(dx: 0.95, dy: 0.80))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.95, dy: 0.49)), withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertEqual(app.staticTexts.matching(identifier: "Yesterday").count, 1)
        shot(app, "Activity timeline")
        let first = app.buttons["workout-900"]
        XCTAssertTrue(first.isHittable)
        XCTAssertTrue((first.value as? String ?? "").contains("6.4"))
        first.tap()
        XCTAssertTrue(app.navigationBars["Strength training"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Recent activities"].waitForExistence(timeout: 5))
        let missing = app.buttons["workout-907"]
        reveal(missing, app: app)
        XCTAssertEqual(missing.value as? String, "Load unavailable")
        shot(app, "Activity timeline missing load")
    }
    func testLargeTextRowsRemainReadableAndOpenDetails() {
        let app = launch(large: true)
        let row = app.buttons["workout-900"]
        XCTAssertTrue(row.waitForExistence(timeout: 15)); reveal(row, app: app)
        app.coordinate(withNormalizedOffset: .init(dx: 0.95, dy: 0.80))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.95, dy: 0.48)), withVelocity: .slow, thenHoldForDuration: 0.3)
        shot(app, "Activity timeline large text")
        if !row.isHittable { app.swipeDown() }
        row.tap()
        XCTAssertTrue(app.navigationBars["Strength training"].waitForExistence(timeout: 10))
    }
    func testEmptyTimelineKeepsRemovedWorkoutsReachable() {
        let app = launch(empty: true)
        XCTAssertTrue(app.staticTexts["No activities yet"].waitForExistence(timeout: 15))
        shot(app, "Activity timeline empty")
        app.buttons["removedWorkouts"].tap()
        XCTAssertTrue(app.navigationBars["Removed workouts"].waitForExistence(timeout: 10))
    }
}
