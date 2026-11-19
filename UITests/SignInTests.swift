import XCTest

@MainActor final class SignInTests: XCTestCase {
    func testRejectedLoginThenSuccessfulLoginPersistsAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarded", "YES", "-resetAuthTest", "-serverURL", "http://127.0.0.1:28476"]
        app.launch()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 8))
        app.textFields["Email"].tap(); app.textFields["Email"].typeText("owner@example.test")
        app.secureTextFields["Password"].tap(); app.secureTextFields["Password"].typeText("wrong-password")
        app.buttons["Sign in"].tap()
        XCTAssertTrue(app.staticTexts["Email or password wasn’t accepted."].waitForExistence(timeout: 8))
        let field = app.secureTextFields["Password"]
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 14) + "synthetic-password")
        app.buttons["Sign in"].tap()
        guard app.buttons["Activity"].waitForExistence(timeout: 12) else {
            let image = XCTAttachment(screenshot: app.screenshot()); image.lifetime = .keepAlways; add(image)
            XCTFail("Sign-in did not reach the dashboard"); return
        }
        app.terminate()
        app.launchArguments = ["-onboarded", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Activity"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.textFields["Email"].exists)
    }
}
