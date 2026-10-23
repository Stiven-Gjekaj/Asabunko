import XCTest

/// Pastes the Aidoku list of scripts/test-server.py, installs its WebAssembly source, and reads a
/// chapter of it. Give the URL of the server in TEST_RUNNER_SERVER_URL.
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
        app.tabBars.buttons["Browse"].tap()
        app.buttons["Add sources"].tap()
        let box = app.textViews["Source list"]
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        box.tap()
        box.typeText(server + "/aidoku/index.min.json")
        app.buttons["Save"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.staticTexts["Aidoku sources"].waitForExistence(timeout: 5), "The kind of the line comes from its URL.")
        app.buttons.matching(NSPredicate(format: "label CONTAINS '127.0.0.1'")).firstMatch.tap()
        let install = app.buttons["Install"]
        XCTAssertTrue(install.waitForExistence(timeout: 10))
        install.tap()
        XCTAssertTrue(app.buttons["Remove"].waitForExistence(timeout: 10), "The package downloads.")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Test Aidoku'")).firstMatch.tap()
        let series = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Aidoku Sunrise'")).firstMatch
        XCTAssertTrue(series.waitForExistence(timeout: 10), "The WebAssembly source gives its series.")
        shot("1 Aidoku source")
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
