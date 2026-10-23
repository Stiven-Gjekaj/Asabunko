import XCTest

/// Uses the filter and the setting of the LNReader plugin of scripts/test-server.py.
/// Give the URL of the server in TEST_RUNNER_SERVER_URL.
final class SourceOptionsTests: XCTestCase {
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

    func testFiltersTheListAndChangesASettingOfASource() throws {
        app.saveSourceLine(server + "/lnreader/plugins.min.json")
        app.waitForInstalled(1)
        app.button(containing: "Quiet Novels").tap()
        XCTAssertTrue(app.button(containing: "Dawn Tea").waitForExistence(timeout: 10))

        app.buttons["Filters"].tap()
        let shelf = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Shelf'")).firstMatch
        XCTAssertTrue(shelf.waitForExistence(timeout: 5), "The sheet shows the filter of the plugin.")
        shelf.tap()
        app.buttons["Finished"].tap()
        shot("1 Filters")
        app.buttons["Apply"].tap()
        XCTAssertTrue(app.button(containing: "Finished Shelf").waitForExistence(timeout: 10), "The plugin gets the value of the filter.")
        XCTAssertFalse(app.button(containing: "Dawn Tea").exists)
        XCTAssertEqual(app.buttons["Filters"].value as? String, "On")
        shot("2 Filtered list")

        app.buttons["Source settings"].tap()
        let stars = app.switches["Show stars"]
        XCTAssertTrue(stars.waitForExistence(timeout: 5), "The settings of the plugin show.")
        stars.switches.firstMatch.tap()
        shot("3 Source settings")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.button(containing: "Quiet Novels").tap()
        XCTAssertTrue(app.button(containing: "\u{2605} Dawn Tea").waitForExistence(timeout: 10), "The plugin reads the new value of the setting.")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
