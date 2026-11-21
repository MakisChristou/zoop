import XCTest

@MainActor final class SignInTests: XCTestCase {
    override func setUp() {
        super.setUp()
        addUIInterruptionMonitor(withDescription: "System password prompt") { sheet in
            if sheet.buttons["Not Now"].exists { sheet.buttons["Not Now"].tap(); return true }
            return false
        }
    }

    private func dismissSavePassword() {
        let button = XCUIApplication().buttons["Not Now"]
        if button.waitForExistence(timeout: 6) { button.tap() }
    }

    func testAccountDeletionRequiresPasswordThenReturnsToSignIn() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarded", "YES", "-demoSerial", "UI-REVIEW", "-resetAuthTest", "-serverURL", "http://127.0.0.1:28476"]
        app.launch()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 8))
        app.textFields["Email"].tap(); app.textFields["Email"].typeText("owner@example.test")
        app.secureTextFields["Password"].tap(); app.secureTextFields["Password"].typeText("synthetic-password")
        app.buttons["Sign in"].tap()
        XCTAssertTrue(app.buttons["openProfile"].waitForExistence(timeout: 12))
        dismissSavePassword()
        app.buttons["openProfile"].tap()
        // The first tap may dismiss the system password prompt through the monitor.
        if !app.buttons["Account"].waitForExistence(timeout: 2) { app.buttons["openProfile"].tap() }
        XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout: 5))
        app.buttons["Account"].tap()
        app.buttons["Delete account"].tap()
        XCTAssertTrue(app.secureTextFields["Confirm your password"].waitForExistence(timeout: 8))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Account deletion"; shot.lifetime = .keepAlways; add(shot)
        app.secureTextFields["Confirm your password"].tap()
        app.secureTextFields["Confirm your password"].typeText("wrong")
        app.buttons["confirmDeleteAccount"].tap()
        XCTAssertTrue(app.staticTexts["Email or password wasn’t accepted."].waitForExistence(timeout: 8))
        app.secureTextFields["Confirm your password"].tap()
        app.secureTextFields["Confirm your password"].typeText("synthetic-password")
        app.buttons["confirmDeleteAccount"].tap()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 12))
        app.terminate(); app.launchArguments = ["-onboarded", "YES", "-demoSerial", "UI-REVIEW"]; app.launch()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 8))
    }

    func testRejectedLoginThenSuccessfulLoginPersistsAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarded", "YES", "-demoSerial", "UI-REVIEW", "-resetAuthTest", "-serverURL", "http://127.0.0.1:28476"]
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
        dismissSavePassword()
        guard app.buttons["Activity"].waitForExistence(timeout: 12) else {
            let image = XCTAttachment(screenshot: app.screenshot()); image.lifetime = .keepAlways; add(image)
            XCTFail("Sign-in did not reach the dashboard"); return
        }
        app.terminate()
        app.launchArguments = ["-onboarded", "YES", "-demoSerial", "UI-REVIEW"]
        app.launch()
        XCTAssertTrue(app.buttons["Activity"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.textFields["Email"].exists)
    }
}
