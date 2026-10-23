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

    func testDiscoversAPaperbackTitleAndReadsAChapter() throws {
        app.saveSourceLine(server + "/paperback/versioning.json")
        XCTAssertTrue(app.staticTexts["Paperback extensions"].waitForExistence(timeout: 5))
        app.waitForInstalled(1)

        app.tabBars.buttons["Discover"].tap()
        let series = app.button(containing: "Paper Moon")
        XCTAssertTrue(series.waitForExistence(timeout: 15), "Discover shows the popular titles of the extension.")
        XCTAssertTrue(app.staticTexts["Popular comics"].exists)
        shot("1 Discover with a Paperback extension")
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
