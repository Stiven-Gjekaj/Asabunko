import XCTest

/// Pastes the Paperback repository of scripts/test-server.py, installs its extension, and reads a
/// chapter. The pages need the referer of the interceptor of the extension.
final class PaperbackTests: XCTestCase {
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

    func testInstallsAPaperbackExtensionAndReadsAChapter() throws {
        app.tabBars.buttons["Browse"].tap()
        app.buttons["Add sources"].tap()
        let box = app.textViews["Source list"]
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        box.tap()
        box.typeText(server + "/paperback/versioning.json")
        app.buttons["Save"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.staticTexts["Paperback extensions"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label CONTAINS '127.0.0.1'")).firstMatch.tap()
        let install = app.buttons["Install"]
        XCTAssertTrue(install.waitForExistence(timeout: 10))
        install.tap()
        XCTAssertTrue(app.buttons["Remove"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Quiet Paper'")).firstMatch.tap()
        let series = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Paper Moon'")).firstMatch
        XCTAssertTrue(series.waitForExistence(timeout: 10), "The extension gives its discover section.")
        shot("1 Paperback extension")
        series.tap()
        let chapter = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Ch. 1: Lanterns'")).firstMatch
        XCTAssertTrue(chapter.waitForExistence(timeout: 10))
        shot("2 Paperback series")
        chapter.tap()
        XCTAssertTrue(app.staticTexts["1 of 2"].waitForExistence(timeout: 15))
        sleep(2)
        shot("3 Paperback page")
        app.buttons["Close"].tap()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
