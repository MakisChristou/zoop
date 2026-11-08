import XCTest

@MainActor final class MeasurementEntryTests: XCTestCase {
    private func launch(screen: String = "", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "WEIGHT-EMPTY-" + UUID().uuidString, "-serverURL", "http://127.0.0.1:28476", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", screen, "-weightUnit", "kg"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func replace(_ field: XCUIElement, with value: String) {
        // Place the caret after the value; tapping its centre can leave a trailing
        // digit on narrow screens when sending backward-delete keystrokes.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        if let current = field.value as? String { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)) }
        field.typeText(value)
    }
    func testWeightRulerTypingAndCancel() {
        let app = launch(), card = app.buttons["todayWeight"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20)); card.tap()
        let log = app.buttons["logWeight"]
        XCTAssertTrue(log.waitForExistence(timeout: 10)); log.tap()
        let input = app.textFields["weightInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let previous = input.value as? String
        let ruler = app.descendants(matching: .any)["weightRuler"].firstMatch
        XCTAssertTrue(ruler.exists)
        shot(app, "Weight ruler starts at last reading")
        ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).press(forDuration: 0.1, thenDragTo: ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)))
        XCTAssertNotEqual(input.value as? String, previous)
        replace(input, with: "74.8")
        XCTAssertEqual(input.value as? String, "74.8")
        XCTAssertTrue(app.buttons["saveWeight"].isEnabled)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(log.waitForExistence(timeout: 5)); log.tap()
        XCTAssertEqual(input.value as? String, previous, "Cancel must not create a measurement")
        app.buttons["Cancel"].tap()
    }
    func testHeightRulerUpdatesOnlyDraftAndCancelPreservesValue() {
        let app = launch(screen: "editprofile")
        let height = app.buttons["editHeight"]
        XCTAssertTrue(height.waitForExistence(timeout: 20)); height.tap()
        let input = app.textFields["heightInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "180")
        let ruler = app.descendants(matching: .any)["heightRuler"].firstMatch
        ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).press(forDuration: 0.1, thenDragTo: ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)))
        XCTAssertNotEqual(input.value as? String, "180")
        shot(app, "Focused height ruler")
        app.buttons["Cancel"].tap(); height.tap()
        XCTAssertEqual(input.value as? String, "180")
        replace(input, with: "178")
        XCTAssertEqual(input.value as? String, "178")
        app.buttons["Done"].tap()
        XCTAssertTrue(height.label.contains("178 cm"), height.label)
        app.terminate(); app.launch()
        XCTAssertTrue(height.waitForExistence(timeout: 20))
        XCTAssertTrue(height.label.contains("180 cm"), "Done edits the draft; Save profile remains explicit")
    }
    func testLargeTextWeightEntryKeepsSaveAndTypingReachable() {
        let app = launch(large: true), card = app.buttons["todayWeight"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        for _ in 0..<5 where !card.isHittable { app.swipeUp() }
        card.tap()
        let log = app.buttons["logWeight"]
        XCTAssertTrue(log.waitForExistence(timeout: 10)); log.tap()
        XCTAssertTrue(app.textFields["weightInput"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saveWeight"].isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["weightRuler"].firstMatch.exists)
        shot(app, "Weight ruler at largest text size")
        app.buttons["Cancel"].tap()
    }
}
