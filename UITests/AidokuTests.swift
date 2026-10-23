import XCTest

/// Pastes the Aidoku list of scripts/test-server.py, which installs its WebAssembly source. Then it
/// searches the source and reads a chapter. Give the URL of the server in TEST_RUNNER_SERVER_URL.
final class AidokuTests: XCTestCase {
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

    func testInstallsAnAidokuSourceAndReadsAChapter() throws {
        app.saveSourceLine(server + "/aidoku/index.min.json")
        XCTAssertTrue(app.staticTexts["Aidoku sources"].waitForExistence(timeout: 5), "The kind of the line comes from its URL.")
        app.waitForInstalled(1)
        XCTAssertTrue(app.button(containing: "Test Aidoku").exists, "The package downloads.")

        app.search("sunrise")
        let series = app.button(containing: "Aidoku Sunrise")
        XCTAssertTrue(series.waitForExistence(timeout: 10), "The WebAssembly source gives its series to the search.")
        shot("1 Search in the Aidoku source")
        series.tap()
        let chapter = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Ch. 1: Opening'")).firstMatch
        XCTAssertTrue(chapter.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Wasm Artist"].exists)
        shot("2 Aidoku series")
        chapter.tap()
        XCTAssertTrue(app.staticTexts["1 of 2"].waitForExistence(timeout: 15), "The source gives the pages.")
        sleep(2)
        shot("3 Aidoku page")
        app.buttons["Close"].tap()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
