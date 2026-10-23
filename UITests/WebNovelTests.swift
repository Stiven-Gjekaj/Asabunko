import XCTest

/// Pastes the LNReader list of scripts/test-server.py, installs its plugin, finds a novel, adds it
/// to the library, and reads a chapter that downloads. Give the URL of the server in
/// TEST_RUNNER_SERVER_URL, such as http://127.0.0.1:8765. With no URL, the test is skipped.
final class WebNovelTests: XCTestCase {
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

    func testInstallsAPluginAndReadsAWebNovel() throws {
        app.saveSourceLine(server + "/lnreader/plugins.min.json")
        app.waitForInstalled(1)
        shot("1 Installed plugin")

        app.search("dawn")
        let novel = app.button(containing: "Dawn Tea")
        XCTAssertTrue(novel.waitForExistence(timeout: 10), "The search asks the plugin.")
        shot("2 Search")
        novel.tap()
        XCTAssertTrue(app.buttons["Add to the read list"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.button(containing: "Second Cup").exists)
        app.buttons["Add to the read list"].tap()
        XCTAssertTrue(app.buttons["Remove from the read list"].waitForExistence(timeout: 5))
        shot("3 Novel of the source")

        app.buttons.matching(NSPredicate(format: "label CONTAINS 'First Cup'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Chapter 1 of 2"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS 'kettle sang'")).firstMatch.waitForExistence(timeout: 10),
                      "The chapter downloads and shows.")
        shot("4 Web novel chapter")
        app.buttons["Next chapter"].tap()
        XCTAssertTrue(app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Rain came'")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["Close"].tap()

        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Chapter 2 of 2"].waitForExistence(timeout: 5), "The novel is in Continue reading with its place.")
        XCTAssertTrue(app.staticTexts["Read list"].exists, "The bookmarked novel is in the read list.")
        shot("5 Library with a web novel")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
