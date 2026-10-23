import XCTest

/// Checks the Paperback title of scripts/test-server.py for a new chapter with the check of the background.
/// The notification opens the book, the Updates list shows the chapter, and the chapter downloads by itself.
final class UpdatesTests: XCTestCase {
    private var app: XCUIApplication!
    private var server = ""
    private var root = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let url = ProcessInfo.processInfo.environment["SERVER_URL"], !url.isEmpty else { throw XCTSkip("SERVER_URL is not set.") }
        server = url
        control("online")
        control("fewer-chapters")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)").path
        app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = root
        app.launch()
    }

    override func tearDown() {
        control("online")
        control("fewer-chapters")
    }

    private func control(_ state: String) {
        let done = expectation(description: state)
        URLSession.shared.dataTask(with: URL(string: server + "/control/" + state)!) { _, _, _ in done.fulfill() }.resume()
        wait(for: [done], timeout: 10)
    }

    func testFindsANewChapterInTheBackgroundAndDownloadsIt() throws {
        app.saveSourceLine(server + "/paperback/versioning.json")
        app.waitForInstalled(1)
        app.button(containing: "Quiet Paper").tap()
        let series = app.button(containing: "Paper Moon")
        XCTAssertTrue(series.waitForExistence(timeout: 15))
        series.tap()
        XCTAssertTrue(app.buttons["Add to the read list"].waitForExistence(timeout: 10))
        app.buttons["Add to the read list"].tap()
        app.buttons["Downloads"].tap()
        app.buttons["Download new chapters"].tap()

        // The checks need the notifications. iOS asks for them one time.
        app.tabBars.buttons["Settings"].tap()
        let checks = app.switches["Check in the background"]
        XCTAssertTrue(checks.waitForExistence(timeout: 5))
        checks.switches.firstMatch.tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        XCTAssertTrue(allow.waitForExistence(timeout: 10), "iOS asks for the notifications.")
        allow.tap()
        XCTAssertEqual(checks.value as? String, "1")

        // The source gets a new chapter. The app starts again and runs the check of the background.
        control("more-chapters")
        app.terminate()
        app.launchEnvironment["ASABUNKO_CHECK_NOW"] = "1"
        app.launch()
        let banner = XCUIApplication(bundleIdentifier: "com.apple.springboard").descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Paper Moon' AND label CONTAINS 'new chapter'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 30), "A notification tells about the new chapter.")
        shot("1 Notification of a new chapter")
        banner.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10), "The notification opens the book.")
        app.buttons["Close"].tap()

        // The Updates list has the new chapter, and the chapter is on the device.
        let updates = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Updates'")).firstMatch
        XCTAssertTrue(updates.waitForExistence(timeout: 10), "The Library shows the updates.")
        updates.tap()
        let chapter = app.button(containing: "Lamps")
        XCTAssertTrue(chapter.waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["Downloaded"].waitForExistence(timeout: 20), "The new chapter downloads by itself.")
        shot("2 Updates")
        control("offline")
        chapter.tap()
        let page = app.images["Page 1"]
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        let deadline = Date().addingTimeInterval(10)
        while page.value as? String != "Loaded" && Date() < deadline { sleep(1) }
        XCTAssertEqual(page.value as? String, "Loaded", "The new chapter reads from the device with the server off.")
        shot("3 New chapter with no network")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
