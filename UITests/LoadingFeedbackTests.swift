import XCTest

@MainActor final class LoadingFeedbackTests: XCTestCase {
    private func check(_ screen: String) async throws {
        let app = XCUIApplication()
        let serial = "RINGS-HELD-" + UUID().uuidString
        app.launchArguments = ["-demoSerial", serial,
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
            try await Task.sleep(for: .milliseconds(300))
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
        // Release only after the anchoring assertions. A fixed server sleep races
        // slower CI accessibility queries and can finish halfway through the test.
        var request = URLRequest(url: URL(string: "http://127.0.0.1:28476/__test/loading/release/" + serial)!)
        request.httpMethod = "POST"
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: indicator)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 25), .completed)
        let loaded = XCTAttachment(screenshot: app.screenshot())
        loaded.name = "Loaded \(screen)"; loaded.lifetime = .keepAlways; add(loaded)
    }
    func testTrendsLoadingCompletes() async throws { try await check("trends") }
    func testActivityLoadingCompletes() async throws { try await check("activity") }
    func testGoalsLoadingStaysAnchoredAndCompletes() async throws { try await check("goals") }
}
