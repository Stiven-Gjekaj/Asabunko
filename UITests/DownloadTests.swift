import XCTest

/// Downloads a chapter of the Aidoku source of scripts/test-server.py, makes the server refuse the
/// pages, and reads the chapter from the device. Give the URL of the server in TEST_RUNNER_SERVER_URL.
final class DownloadTests: XCTestCase {
    private var app: XCUIApplication!
    private var server = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let url = ProcessInfo.processInfo.environment["SERVER_URL"], !url.isEmpty else { throw XCTSkip("SERVER_URL is not set.") }
        server = url
        control("online")
        app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)").path
        app.launch()
    }

    override func tearDown() {
        control("online")
    }

    /// Turns the pages of the server on or off.
    private func control(_ state: String) {
        let done = expectation(description: state)
        URLSession.shared.dataTask(with: URL(string: server + "/control/" + state)!) { _, _, _ in done.fulfill() }.resume()
        wait(for: [done], timeout: 10)
    }

    func testReadsADownloadedChapterWithNoNetwork() throws {
        app.saveSourceLine(server + "/aidoku/index.min.json")
        app.waitForInstalled(1)
        app.search("sunrise")
        let series = app.button(containing: "Aidoku Sunrise")
        XCTAssertTrue(series.waitForExistence(timeout: 10))
        series.tap()

        XCTAssertTrue(app.buttons["Add to the read list"].waitForExistence(timeout: 10))
        app.buttons["Add to the read list"].tap()
        XCTAssertTrue(app.buttons["Downloads"].waitForExistence(timeout: 10))
        app.buttons["Downloads"].tap()
        app.buttons["Download all chapters"].tap()
        XCTAssertTrue(app.images["Downloaded"].waitForExistence(timeout: 20), "The chapter downloads.")
        shot("1 Downloaded chapter")

        control("offline")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Ch. 1: Opening'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["1 of 2"].waitForExistence(timeout: 10))
        let page = app.images["Page 1"]
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        let deadline = Date().addingTimeInterval(10)
        while page.value as? String != "Loaded" && Date() < deadline { sleep(1) }
        XCTAssertEqual(page.value as? String, "Loaded", "The page comes from the device, because the server refuses it.")
        shot("2 Downloaded page with the server off")
        app.buttons["Close"].tap()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
