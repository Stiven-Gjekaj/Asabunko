import XCTest

/// Saves the source list many times. Each save installs the English sources that are not on the device,
/// and removes the sources of the lines that the user removed. The other sources do not download again.
/// The device is in Japanese, so a Japanese source of the list would install if the app used the device languages.
final class SourceSyncTests: XCTestCase {
    private var app: XCUIApplication!
    private var server = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let url = ProcessInfo.processInfo.environment["SERVER_URL"], !url.isEmpty else { throw XCTSkip("SERVER_URL is not set.") }
        server = url
        app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)").path
        app.launchArguments += ["-AppleLanguages", "(ja)"]
        app.launch()
    }

    func testEachSaveInstallsOnlyTheChangedEnglishSources() throws {
        let start = try downloads()
        let aidoku = server + "/aidoku/index.min.json", paperback = server + "/paperback/versioning.json"
        app.saveSourceLine(aidoku)
        app.waitForInstalled(1)
        XCTAssertTrue(app.button(containing: "Test Aidoku").exists)
        XCTAssertFalse(app.button(containing: "Japanese Test").exists, "A Japanese source does not install.")
        XCTAssertEqual(try downloads() - start, 1)

        // The rest of the test edits the text of the list, and the edit menu of iOS has the language of the device.
        // So the app starts again in English, with the same library.
        app.terminate()
        app.launchArguments = []
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sources'")).firstMatch.tap()
        app.waitForInstalled(1)

        // A second line installs its sources. The source of the first line does not download again.
        save(aidoku + "\n" + paperback)
        app.waitForInstalled(2)
        XCTAssertEqual(try downloads() - start, 1, "A save does not install a source that is on the device.")

        // A source that the user removed comes back at the next save.
        let row = app.button(containing: "Test Aidoku")
        row.swipeLeft()
        app.buttons["Remove"].tap()
        app.waitForInstalled(1)
        save(aidoku + "\n" + paperback)
        app.waitForInstalled(2)
        XCTAssertEqual(try downloads() - start, 2)

        // The sources of a removed line go.
        save(aidoku)
        app.waitForInstalled(1)
        XCTAssertFalse(app.button(containing: "Quiet Paper").exists, "The source of the removed line goes.")
        XCTAssertTrue(app.button(containing: "Test Aidoku").exists)
        XCTAssertEqual(try downloads() - start, 2)
    }

    /// Replaces the text of the source list and saves it. The Sources page stays open.
    private func save(_ text: String) {
        app.buttons["Edit the source list"].tap()
        let box = app.textViews["Source list"]
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        // Select All of the edit menu selects the old text, and the new text takes its place.
        box.tap()
        box.press(forDuration: 1.2)
        let all = app.menuItems["Select All"]
        XCTAssertTrue(all.waitForExistence(timeout: 5), "The edit menu shows.")
        all.tap()
        box.typeText(text)
        XCTAssertEqual(box.value as? String, text, "The box has only the new list.")
        app.buttons["Save"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// The number of downloads of the Aidoku package from the test server.
    private func downloads() throws -> Int {
        let text = try String(contentsOf: URL(string: server + "/aidoku/downloads")!, encoding: .utf8)
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
    }
}
