import XCTest

/// Pastes the small Suwayomi server of scripts/test-server.py with its account, shows its source,
/// and reads a chapter from it. Give the URL of the server in TEST_RUNNER_SERVER_URL.
final class ServerComicTests: XCTestCase {
    private var app: XCUIApplication!
    private var server = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let url = ProcessInfo.processInfo.environment["SERVER_URL"], !url.isEmpty else { throw XCTSkip("SERVER_URL is not set.") }
        server = url
        app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)").path
        app.launch()
    }

    func testReadsAComicOfASuwayomiServer() throws {
        app.tabBars.buttons["Browse"].tap()
        app.buttons["Add sources"].tap()
        let box = app.textViews["Source list"]
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        box.tap()
        box.typeText(server.replacingOccurrences(of: "http://", with: "http://asa:morning@") + "/suwayomi")
        app.buttons["Save"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons.matching(NSPredicate(format: "label CONTAINS '127.0.0.1'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Show"].waitForExistence(timeout: 10), "The server gives its sources with the password.")
        XCTAssertFalse(app.staticTexts["Local source"].exists)
        shot("1 Server sources")
        app.buttons["Show"].tap()
        XCTAssertTrue(app.buttons["Hide"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Test Comics (EN)'")).firstMatch.tap()
        let series = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Morning Strip'")).firstMatch
        XCTAssertTrue(series.waitForExistence(timeout: 10))
        series.tap()
        let chapter = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Chapter 1'")).firstMatch
        XCTAssertTrue(chapter.waitForExistence(timeout: 10))
        shot("2 Series of the server")
        chapter.tap()
        XCTAssertTrue(app.staticTexts["1 of 3"].waitForExistence(timeout: 15), "The pages come from the server.")
        sleep(2)
        shot("3 Page of the server")
        app.buttons["Close"].tap()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Chapter 1 of 1"].waitForExistence(timeout: 5))
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
