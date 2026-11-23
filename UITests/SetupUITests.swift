import XCTest

@MainActor final class SetupUITests: XCTestCase {
    private func launchPreview(large: Bool = false, light: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "SETUP-PREVIEW", "-demoScreen", "profile",
            "-serverURL", "http://127.0.0.1:28476", "-ingestToken", "ui-test-token", "-onboarded", "YES"]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        if light { app.launchArguments += ["-AppleInterfaceStyle", "Light"] }
        app.launchSynthetic()
        let preview = app.buttons["previewSetup"]
        XCTAssertTrue(app.navigationBars["Profile & settings"].waitForExistence(timeout: 10))
        for _ in 0..<12 { if preview.exists && preview.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(preview.isHittable)
        preview.tap()
        XCTAssertTrue(app.buttons["closeSetupPreview"].waitForExistence(timeout: 5))
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        // Capture the settled screen, not UIKit’s button highlight or sheet transition.
        let settled = expectation(description: "Screen settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    func testPreviewAllScreensAndReturnToExistingAccount() {
        let app = launchPreview()
        shot(app, "Setup 1 Welcome")
        app.buttons["setupPrimary"].tap()
        XCTAssertEqual(app.textFields["setupServer"].value as? String, "https://zoop.example.com")
        XCTAssertFalse(app.textFields["setupServer"].isEnabled)
        shot(app, "Setup 2 Server")
        app.buttons["setupPrimary"].tap()
        XCTAssertTrue(app.buttons["setupSkipBand"].waitForExistence(timeout: 5))
        shot(app, "Setup 3 WHOOP")
        app.buttons["setupPrimary"].tap()
        XCTAssertTrue(app.staticTexts["You’re connected"].waitForExistence(timeout: 5))
        shot(app, "Setup 4 Ready")
        app.buttons["setupPrimary"].tap()
        XCTAssertTrue(app.navigationBars["Profile & settings"].waitForExistence(timeout: 5))
        app.buttons["previewSetup"].tap()
        XCTAssertEqual(app.buttons["setupPrimary"].label, "Get started")
        app.buttons["closeSetupPreview"].tap()
        app.buttons["Account"].tap()
        XCTAssertTrue(app.staticTexts["http://127.0.0.1:28476"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Sign out"].exists)
        XCTAssertFalse(app.buttons["Show the welcome guide again"].exists)
    }
    func testPreviewSkipBandAndCancelAtAnyStep() {
        let app = launchPreview()
        app.buttons["setupPrimary"].tap(); app.buttons["setupPrimary"].tap()
        app.buttons["setupSkipBand"].tap()
        XCTAssertTrue(app.staticTexts["You’re signed in"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["First sync"].exists)
        app.buttons["setupBack"].tap(); app.buttons["setupBack"].tap()
        app.buttons["closeSetupPreview"].tap()
        XCTAssertTrue(app.buttons["previewSetup"].waitForExistence(timeout: 5))
    }
    func testLargeTextAndLightAppearanceRemainUsable() {
        let app = launchPreview(large: true, light: true)
        shot(app, "Setup large text welcome")
        for step in 0..<4 {
            let primary = app.buttons["setupPrimary"]
            XCTAssertTrue(primary.isHittable)
            if step == 1 {
                let email = app.textFields["setupEmail"]
                for _ in 0..<6 { if email.isHittable { break }; app.scrollViews["setupScroll"].swipeUp() }
                XCTAssertTrue(email.isHittable)
                shot(app, "Setup large text form")
            }
            primary.tap()
        }
        XCTAssertTrue(app.buttons["previewSetup"].waitForExistence(timeout: 5))
    }
    func testFirstRunSignsInWithoutRestartingWizardAndCanSkipBand() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarded", "NO", "-demoScreen", "setup", "-demoSerial", "", "-resetAuthTest"]
        app.launchSynthetic()
        XCTAssertTrue(app.buttons["setupPrimary"].waitForExistence(timeout: 8))
        app.buttons["setupPrimary"].tap()
        XCTAssertFalse(app.buttons["setupPrimary"].isEnabled)
        app.textFields["setupServer"].tap(); app.textFields["setupServer"].typeText("http://127.0.0.1:28476\n")
        app.textFields["setupEmail"].typeText("owner@example.test\n")
        // Use the form’s Next/Go actions; offscreen fields move with keyboard focus.
        app.secureTextFields["setupPassword"].typeText("synthetic-password\n")
        XCTAssertTrue(app.buttons["setupSkipBand"].waitForExistence(timeout: 10))
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 2) { notNow.tap() }
        app.buttons["setupSkipBand"].tap(); app.buttons["setupPrimary"].tap()
        XCTAssertTrue(app.buttons["openProfile"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = ["-demoScreen", "setup", "-demoSerial", ""]
        app.launchSynthetic()
        XCTAssertTrue(app.buttons["openProfile"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["setupPrimary"].exists)
    }
}
