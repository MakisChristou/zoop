import XCTest

@MainActor final class ProfileUITests: XCTestCase {
    private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial","PROFILE-UI","-demoScreen","profile","-serverURL","http://127.0.0.1:28480","-ingestToken","ui-test-token","-onboarded","YES","-weightUnit","kg"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.navigationBars["Profile & settings"].waitForExistence(timeout: 10))
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable { break }
            let weightScroll = app.scrollViews["weightScroll"]
            if weightScroll.exists {
                let start = weightScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.8))
                let end = weightScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.2))
                start.press(forDuration: 0.05, thenDragTo: end)
            } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }
    func testLatestProfileWeightAndImportStayFindable() {
        let app = launch()
        shot(app,"Profile hub")
        app.buttons["Edit profile"].tap()
        let weight = app.buttons["profileLatestWeight"]
        XCTAssertTrue(weight.waitForExistence(timeout: 10)); XCTAssertTrue(weight.label.contains("75.2"))
        XCTAssertFalse(app.textFields["Weight in kilograms"].exists)
        shot(app,"Profile follows the latest Health weight")
        weight.tap()
        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 5))
        let importer = app.buttons["openWeightImport"]
        XCTAssertTrue(importer.waitForExistence(timeout: 10)); scrollTo(importer,in:app); importer.tap()
        XCTAssertTrue(app.navigationBars["Import weight history"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["confirmWeightImport"].exists)
        app.buttons["closeWeightImport"].tap(); scrollTo(importer,in:app); importer.tap()
        XCTAssertTrue(app.navigationBars["Import weight history"].waitForExistence(timeout: 5))
        shot(app,"Weight import can be reopened")
    }
    func testPhotoPickerIsAvailableAndCanBeCancelled() {
        let app = launch()
        app.buttons["editProfilePhoto"].tap()
        XCTAssertTrue(app.navigationBars["Profile photo"].waitForExistence(timeout: 5))
        shot(app,"Profile photo editor")
        app.buttons["chooseProfilePhoto"].tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8))
        let loaded = NSPredicate(format: "exists == false")
        let load = XCTNSPredicateExpectation(predicate: loaded, object: app.staticTexts["Loading…"].firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [load], timeout: 20), .completed)
        shot(app,"Native selected-photo picker")
        let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "Photo picker hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        cancel.tap()
        XCTAssertTrue(app.navigationBars["Profile photo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["saveProfilePhoto"].exists)
        for _ in 0..<2 {
            app.buttons["chooseProfilePhoto"].tap()
            XCTAssertTrue(cancel.waitForExistence(timeout: 8))
            cancel.tap()
            XCTAssertTrue(app.buttons["chooseProfilePhoto"].waitForExistence(timeout: 5))
        }
    }
    func testLargeTextProfileControlsRemainReachable() {
        let app = launch(large: true)
        let photo = app.buttons["editProfilePhoto"]; scrollTo(photo,in:app); photo.tap()
        XCTAssertTrue(app.buttons["chooseProfilePhoto"].waitForExistence(timeout: 5))
        scrollTo(app.buttons["chooseProfilePhoto"],in:app)
        shot(app,"Profile photo at accessibility text size")
        app.buttons["closeProfilePhoto"].tap()
        scrollTo(app.buttons["Edit profile"],in:app); app.buttons["Edit profile"].tap()
        let weight = app.buttons["profileLatestWeight"]
        XCTAssertTrue(weight.waitForExistence(timeout: 10)); scrollTo(weight,in:app)
        shot(app,"Latest profile weight at accessibility text size")
    }
    func testPhotoUploadSurvivesRelaunchAndCanBeRemoved() {
        let app = launch()
        app.buttons["editProfilePhoto"].tap()
        app.buttons["chooseProfilePhoto"].tap()
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 20)); photo.tap()
        let save = app.buttons["saveProfilePhoto"]
        XCTAssertTrue(save.waitForExistence(timeout: 20)); shot(app,"Prepared profile photo"); save.tap()
        let changed = app.buttons["editProfilePhoto"]
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Change photo"), object: changed)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 10), .completed)
        app.terminate(); app.launch()
        XCTAssertTrue(changed.waitForExistence(timeout: 10))
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Change photo"), object: changed)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed)
        shot(app,"Saved profile photo after relaunch")
        changed.tap(); app.buttons["Remove photo"].tap()
        app.buttons.matching(identifier: "confirmRemoveProfilePhoto").firstMatch.tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Add photo"), object: changed)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 10), .completed)
    }
}
