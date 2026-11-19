import XCTest

@MainActor final class SleepStagesLayoutTests: XCTestCase {
    private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "SLEEP-LAYOUT", "-serverURL", "http://127.0.0.1:28476",
            "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", "sleep",
            "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.buttons["Sleep options"].waitForExistence(timeout: 20))
        return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication, centered: Bool = false) {
        for _ in 0..<16 {
            if !element.exists { app.swipeUp(velocity: .slow); continue }
            let frame = element.frame
            if element.isHittable && frame.minY > 110 && frame.maxY < app.buttons["tab-Sleep"].frame.minY - 10 && (!centered || abs(frame.midY - app.frame.height * 0.45) < 30) { break }
            let delta = min(max((frame.midY - app.frame.height * 0.45) / app.frame.height, -0.25), 0.25)
            app.coordinate(withNormalizedOffset: .init(dx: 0.85, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.85, dy: 0.5 - delta)), withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(element.isHittable)
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    func testCardAlignsReadingsAndRetainsComparisons() {
        let app = launch()
        reveal(app.staticTexts["stageDuration-Light"], app: app, centered: true)
        let deep = app.staticTexts["stageDuration-Deep"], rem = app.staticTexts["stageDuration-REM"]
        XCTAssertEqual(deep.label, "1h 25m")
        XCTAssertEqual(rem.label, "1h 35m")
        XCTAssertEqual(app.staticTexts["stageDuration-Light"].label, "4h 25m")
        XCTAssertEqual(app.staticTexts["stageDuration-Awake"].label, "5m")
        XCTAssertEqual(deep.frame.minX, app.staticTexts["sleepStageOnset"].frame.minX, accuracy: 1)
        XCTAssertEqual(rem.frame.minX, app.staticTexts["sleepStageOffset"].frame.minX, accuracy: 1)
        for stage in ["Deep", "REM", "Light"] {
            let delta = app.staticTexts["sleepDelta-" + stage]
            XCTAssertTrue(delta.isHittable)
            XCTAssertTrue(delta.label.contains("average"))
            XCTAssertLessThan(delta.frame.maxY, app.staticTexts["stageDuration-" + stage].frame.minY)
        }
        shot(app, "Sleep stages aligned card")
    }
    func testLargestTextKeepsStageReadingsAndTimesReachable() {
        let app = launch(large: true)
        for stage in ["Deep", "REM", "Light", "Awake"] {
            let duration = app.staticTexts["stageDuration-" + stage]
            reveal(duration, app: app)
            if stage != "Awake" { XCTAssertTrue(app.staticTexts["sleepDelta-" + stage].exists) }
            if stage == "Deep" { shot(app, "Sleep stages largest text") }
        }
        reveal(app.staticTexts["sleepStageOffset"], app: app)
        XCTAssertTrue(app.staticTexts["sleepStageOnset"].exists)
        shot(app, "Sleep times largest text")
    }
}
