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
        let done = expectation(description: "reset")
        URLSession.shared.dataTask(with: URL(string: server + "/control/reset")!) { _, _, _ in done.fulfill() }.resume()
        wait(for: [done], timeout: 10)
        app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)").path
        app.launch()
    }

    func testReadsAComicOfASuwayomiServer() throws {
        app.saveSourceLine(server.replacingOccurrences(of: "http://", with: "http://asa:morning@") + "/suwayomi")
        app.waitForInstalled(1)
        XCTAssertFalse(app.staticTexts["Local source"].exists, "The local source of the server has no language of the device.")
        shot("1 Server sources")

        app.button(containing: "Test Comics (EN)").tap()
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

    func testFiltersTheListAndChangesAPreferenceOfAServerSource() throws {
        app.saveSourceLine(server.replacingOccurrences(of: "http://", with: "http://asa:morning@") + "/suwayomi")
        app.waitForInstalled(1)
        app.button(containing: "Test Comics (EN)").tap()
        XCTAssertTrue(app.button(containing: "Morning Strip").waitForExistence(timeout: 10))

        // A group of genres of the Mihon source is one choice of many values.
        app.buttons["Filters"].tap()
        let genres = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Genres'")).firstMatch
        XCTAssertTrue(genres.waitForExistence(timeout: 5), "The filters of the server show.")
        genres.tap()
        app.buttons["Comedy"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Apply"].tap()
        XCTAssertTrue(app.button(containing: "Comedy Strip").waitForExistence(timeout: 10), "The server gets the change of the filter.")
        shot("4 Filtered list of the server")

        app.buttons["Source settings"].tap()
        let stars = app.switches["Show stars"]
        XCTAssertTrue(stars.waitForExistence(timeout: 5), "The preferences of the source show.")
        stars.switches.firstMatch.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Filters"].tap()
        app.buttons["Reset"].tap()
        app.buttons["Apply"].tap()
        XCTAssertTrue(app.button(containing: "\u{2605} Morning Strip").waitForExistence(timeout: 10), "The server keeps the new preference.")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
