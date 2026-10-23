import XCTest

/// The sign-in to AniList, the link of a book, and the progress that goes to the tracker.
/// The test server acts as AniList.
final class TrackerTests: XCTestCase {
    private var app: XCUIApplication!
    private var server = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        server = ProcessInfo.processInfo.environment["SERVER_URL"] ?? ""
        guard !server.isEmpty else { throw XCTSkip("SERVER_URL is not set.") }
        _ = try? Data(contentsOf: URL(string: server + "/control/reset")!)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)")
        app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = folder.appendingPathComponent("library").path
        app.launchEnvironment["ASABUNKO_TRACKER_BASE"] = server + "/trackers"
        app.launch()
    }

    func testSendsTheProgressOfABookToAniList() throws {
        app.saveSourceLine(server + "/aidoku/index.min.json")
        app.waitForInstalled(1)
        app.search("sunrise")
        let series = app.button(containing: "Aidoku Sunrise")
        XCTAssertTrue(series.waitForExistence(timeout: 15))
        series.tap()
        XCTAssertTrue(app.buttons["Add to the read list"].waitForExistence(timeout: 10))
        app.buttons["Add to the read list"].tap()

        // The sign-in. The Keychain of the simulator can keep a token of an older run.
        app.tabBars.buttons["Settings"].tap()
        if app.navigationBars["Sources"].exists { app.navigationBars.buttons.element(boundBy: 0).tap() }
        let field = app.textFields["AniList client ID"]
        app.tapAfterScroll(app.buttons["Trackers"], opens: field)
        if app.buttons["Sign out of AniList"].exists { app.buttons["Sign out of AniList"].tap() }
        if (field.value as? String ?? "").isEmpty || field.value as? String == "Client ID" {
            field.tap()
            field.typeText("test-client\n")
        }
        // A new simulator shows a tip of the keyboard one time.
        if app.buttons["Continue"].waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
        app.buttons["Sign in to AniList"].tap()
        // iOS asks before the sign-in page opens. That question is not part of the app.
        let proceed = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Continue"]
        if proceed.waitForExistence(timeout: 10) { proceed.tap() }
        XCTAssertTrue(app.buttons["Sign out of AniList"].waitForExistence(timeout: 20), "The app keeps the token of the sign-in.")
        shot("1 Signed in")

        // The link of the book. The sheet searches with the title of the book.
        app.tabBars.buttons["Library"].tap()
        app.button(containing: "Aidoku Sunrise").press(forDuration: 1.2)
        app.buttons["Track"].tap()
        let hit = app.button(containing: "1 chapters")
        XCTAssertTrue(hit.waitForExistence(timeout: 15), "AniList has the title.")
        shot("2 Search")
        hit.tap()

        // A finished book sends all of its chapters.
        app.button(containing: "Aidoku Sunrise").press(forDuration: 1.2)
        app.buttons["Mark as read"].tap()
        let sent = expectation(description: "AniList has the progress")
        poll(until: sent) { state in
            guard let entry = state["anilist"] as? [String: Any] else { return false }
            return entry["id"] as? Int == 101 && entry["progress"] as? Int == 1 && entry["status"] as? String == "COMPLETED"
        }
        wait(for: [sent], timeout: 15)
    }

    /// Reads the state of the fake trackers until the check is true.
    private func poll(until done: XCTestExpectation, check: @escaping @Sendable ([String: Any]) -> Bool) {
        let url = URL(string: server + "/trackers/state")!
        Task.detached {
            for _ in 0..<30 {
                if let data = try? await URLSession.shared.data(from: url).0,
                   let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any], check(state) {
                    done.fulfill()
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
