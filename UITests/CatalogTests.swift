import XCTest

/// Pastes the OPDS server of scripts/test-server.py into the source list, signs in, searches, streams a comic,
/// and downloads it. Start the server first, and give its URL in TEST_RUNNER_OPDS_URL.
/// With no URL, the test is skipped.
final class CatalogTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let url = ProcessInfo.processInfo.environment["OPDS_URL"], !url.isEmpty else {
            throw XCTSkip("OPDS_URL is not set.")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)")
        app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = folder.path
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sources'")).firstMatch.tap()
        app.buttons["Add sources"].tap()
        let box = app.textViews["Source list"]
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        box.tap()
        // The user name and the password are in the line, as in the paste box of ZettaStream.
        box.typeText(url.replacingOccurrences(of: "http://", with: "http://asa:morning@"))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Saved 1 source."].waitForExistence(timeout: 5))
        // The row shows the scheme, the host, and the port of the URL.
        let origin = url.components(separatedBy: "/").prefix(3).joined(separator: "/")
        XCTAssertTrue(app.staticTexts["asa at \(origin)/..."].exists, "The list shows the user name and no password.")
        shot("0 Sources")
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    func testBrowsesStreamsAndDownloadsAComic() throws {
        app.buttons.matching(NSPredicate(format: "label CONTAINS '127.0.0.1'")).firstMatch.tap()
        let all = app.buttons.matching(NSPredicate(format: "label CONTAINS 'All books'")).firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 10), "The catalog opens with the password.")
        shot("1 Catalog")

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("sunrise\n")
        let book = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Server Sunrise 1'")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 10), "The search gives the book.")
        shot("2 Search results")
        // A clear search shows the catalog again.
        let clear = search.buttons["Clear text"]
        if clear.exists { clear.tap() }
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        if app.keyboards.count > 0 { app.swipeDown() }

        all.tap()
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.tap()
        XCTAssertTrue(app.buttons["Read now"].waitForExistence(timeout: 5))
        shot("3 Book")

        app.buttons["Read now"].tap()
        XCTAssertTrue(app.staticTexts["1 of 4"].waitForExistence(timeout: 10))
        sleep(2)
        shot("4 Streamed page")
        app.buttons["Close"].tap()

        app.buttons["Download"].tap()
        XCTAssertTrue(app.buttons["In the library"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Server Sunrise 1'")).firstMatch.waitForExistence(timeout: 10))
        shot("5 Library with the download")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
