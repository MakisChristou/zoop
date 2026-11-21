import XCTest

@MainActor final class LoadingFeedbackTests: XCTestCase {
    private func check(_ screen: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "RINGS-SLOW-" + UUID().uuidString,
            "-serverURL", "http://127.0.0.1:28476", "-ingestToken", "ui-test-token",
            "-onboarded", "YES", "-demoScreen", screen]
        app.launch()
        let indicator = app.descendants(matching: .any).matching(identifier: "loadingIndicator").firstMatch
        XCTAssertTrue(indicator.waitForExistence(timeout: 6))
        let initial = indicator.frame
        XCTAssertEqual(initial.height, 3, accuracy: 1)
        // Sample several animation phases. The segment may move sideways, but
        // its accessibility frame and vertical position must never travel.
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.3)
            XCTAssertEqual(indicator.frame.minY, initial.minY, accuracy: 1)
            XCTAssertEqual(indicator.frame.height, initial.height, accuracy: 1)
        }
        app.swipeUp()
        XCTAssertEqual(indicator.frame.minY, initial.minY, accuracy: 1)
        app.buttons["tab-Today"].tap()
        app.buttons["tab-" + screen.capitalized].tap()
        XCTAssertTrue(indicator.exists)
        XCTAssertEqual(indicator.frame.minY, initial.minY, accuracy: 1)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Loading \(screen)"; image.lifetime = .keepAlways; add(image)
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: indicator)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 25), .completed)
        let loaded = XCTAttachment(screenshot: app.screenshot())
        loaded.name = "Loaded \(screen)"; loaded.lifetime = .keepAlways; add(loaded)
    }
    func testTrendsLoadingCompletes() { check("trends") }
    func testActivityLoadingCompletes() { check("activity") }
    func testGoalsLoadingStaysAnchoredAndCompletes() { check("goals") }
}
