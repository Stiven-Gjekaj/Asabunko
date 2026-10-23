import XCTest

/// Opens a catalog behind the browser check of scripts/test-server.py, passes the check in the
/// web view, and opens the catalog. Give the URL of the server in TEST_RUNNER_SERVER_URL.
final class BrowserCheckTests: XCTestCase {
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

    func testPassesTheBrowserCheckOfASite() throws {
        app.saveSourceLine(server.replacingOccurrences(of: "http://", with: "http://asa:morning@") + "/cf/opds/catalog")
        app.button(containing: "127.0.0.1").tap()
        XCTAssertTrue(app.staticTexts["The catalog did not open"].waitForExistence(timeout: 10))
        let banner = app.staticTexts["127.0.0.1 asks for a check"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "The app finds the check in the answer.")
        shot("1 Banner of the check")

        app.buttons["Open"].tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        // The page sets the cookie and loads again. Then the sheet closes.
        let deadline = Date().addingTimeInterval(20)
        while app.webViews.firstMatch.exists && Date() < deadline { sleep(1) }
        XCTAssertFalse(app.webViews.firstMatch.exists, "The sheet closes when the cookie of the check comes.")
        XCTAssertFalse(banner.exists, "The banner goes after the check.")

        XCTAssertTrue(app.button(containing: "All books").waitForExistence(timeout: 15), "The catalog loads again by itself, with the cookie of the check.")
        shot("2 Catalog after the check")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
