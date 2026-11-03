import XCTest

@MainActor final class ECGUITests: XCTestCase {
    private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoScreen", "ecg", "-onboarded", "YES"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testGuidedPreparationAndDisconnectedState() {
        let app = launch()
        let start = app.buttons["recordECG"]
        XCTAssertTrue(start.waitForExistence(timeout: 10)); snapshot(app, "ECG home")
        start.tap()
        XCTAssertTrue(app.staticTexts["Get comfortable."].waitForExistence(timeout: 5))
        let begin = app.buttons["beginECG"]
        for _ in 0..<5 { if begin.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(begin.exists); XCTAssertFalse(begin.isEnabled)
        XCTAssertTrue(app.buttons["Reconnect"].exists)
        snapshot(app, "ECG preparation offline")
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
    }
    func testPreparationAtAccessibilityTextSize() {
        let app = launch(large: true)
        let start = app.buttons["recordECG"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        for _ in 0..<5 { if start.isHittable { break }; app.swipeUp() }
        start.tap()
        let begin = app.buttons["beginECG"]
        for _ in 0..<12 { if begin.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(begin.isHittable); XCTAssertFalse(begin.isEnabled)
        snapshot(app, "ECG large text preparation")
    }
}
