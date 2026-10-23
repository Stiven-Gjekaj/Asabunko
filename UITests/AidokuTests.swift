import XCTest

/// Pastes the Aidoku list of scripts/test-server.py, which installs its WebAssembly source. Then it
/// searches the source and reads a chapter. Give the URL of the server in TEST_RUNNER_SERVER_URL.
final class AidokuTests: XCTestCase {
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

    func testInstallsAnAidokuSourceAndReadsAChapter() throws {
        app.saveSourceLine(server + "/aidoku/index.min.json")
        XCTAssertTrue(app.staticTexts["Aidoku sources"].waitForExistence(timeout: 5), "The kind of the line comes from its URL.")
        app.waitForInstalled(1)
        XCTAssertTrue(app.button(containing: "Test Aidoku").exists, "The package downloads.")

        app.search("sunrise")
        let series = app.button(containing: "Aidoku Sunrise")
        XCTAssertTrue(series.waitForExistence(timeout: 10), "The WebAssembly source gives its series to the search.")
        shot("1 Search in the Aidoku source")
        series.tap()
        let chapter = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Ch. 1: Opening'")).firstMatch
        XCTAssertTrue(chapter.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Wasm Artist"].exists)
        shot("2 Aidoku series")
        chapter.tap()
        XCTAssertTrue(app.staticTexts["1 of 2"].waitForExistence(timeout: 15), "The source gives the pages.")
        sleep(2)
        shot("3 Aidoku page")
        app.buttons["Close"].tap()
    }

    func testChangesTheSettingsOfTheSource() throws {
        app.saveSourceLine(server + "/aidoku/index.min.json")
        app.waitForInstalled(1)
        app.button(containing: "Test Aidoku").tap()
        XCTAssertTrue(app.button(containing: "Aidoku Sunrise").waitForExistence(timeout: 10))
        app.buttons["Source settings"].tap()

        // The sign-in with a user name and a password. The link needs the sign-in.
        let signIn = app.button(containing: "Sign in")
        XCTAssertTrue(signIn.waitForExistence(timeout: 5), "The settings of settings.json show as a form.")
        XCTAssertFalse(app.button(containing: "Account page").exists)
        XCTAssertTrue(app.staticTexts["The source reads these values."].exists)
        signIn.tap()
        let email = app.alerts.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.typeText("mina@site.test")
        app.alerts.secureTextFields["Password"].tap()
        app.alerts.secureTextFields["Password"].typeText("tea")
        app.alerts.buttons["Sign in"].tap()
        // iOS can offer to keep the password. That dialog is not part of the app.
        // The dialog can come some seconds after the sign-in.
        let save = app.sheets["Save Password?"]
        if save.waitForExistence(timeout: 10) {
            for _ in 0..<3 where save.exists {
                save.buttons["Not Now"].tap()
                let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: save)
                _ = XCTWaiter.wait(for: [gone], timeout: 5)
            }
        }
        XCTAssertFalse(save.exists, "The dialog of iOS closed.")
        XCTAssertTrue(app.button(containing: "Sign out").waitForExistence(timeout: 5), "The row signs out after the sign-in.")
        XCTAssertTrue(app.button(containing: "Account page").exists, "The link shows after the sign-in.")
        XCTAssertTrue(app.staticTexts["mina@site.test"].exists)

        // A choice, and a stepper in its range.
        app.button(containing: "Server").tap()
        XCTAssertTrue(app.button(containing: "Beta").waitForExistence(timeout: 5), "The choices of the setting show.")
        app.button(containing: "Beta").tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Beta' AND label CONTAINS 'Selected'")).firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.button(containing: "Beta").waitForExistence(timeout: 5), "The form shows the new choice.")
        let increment = app.buttons["Increment"]
        for value in ["3", "4", "4"] {
            increment.tap()
            let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: increment)
            XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 5), .completed, "The stepper shows \(value), and it stops at its maximum.")
        }
        shot("5 Aidoku settings")

        // A list in a page, and a button that asks first.
        app.button(containing: "Content filters").tap()
        XCTAssertTrue(app.button(containing: "Blocked tags").waitForExistence(timeout: 5))
        app.button(containing: "Blocked tags").tap()
        let add = app.textFields["Tag"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        add.typeText("gore\n")
        XCTAssertTrue(app.buttons["gore"].waitForExistence(timeout: 5), "The entry goes in the list.")
        app.buttons["gore"].tap()
        XCTAssertFalse(app.buttons["gore"].waitForExistence(timeout: 2), "A tap removes the entry.")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Reset filters"].waitForExistence(timeout: 5))
        app.buttons["Reset filters"].tap()
        XCTAssertTrue(app.staticTexts["Remove all filters?"].waitForExistence(timeout: 5), "The button asks before its action.")
        shot("6 Aidoku page with a button")
    }

    func testFiltersTheSourceWithARange() throws {
        app.saveSourceLine(server + "/aidoku/index.min.json")
        app.waitForInstalled(1)
        app.button(containing: "Test Aidoku").tap()
        XCTAssertTrue(app.button(containing: "Aidoku Sunrise").waitForExistence(timeout: 10))
        app.buttons["Filters"].tap()
        let from = app.textFields["Year, from"]
        XCTAssertTrue(from.waitForExistence(timeout: 5), "The range filter of filters.json shows as two fields.")
        XCTAssertEqual(from.placeholderValue, "1990")
        from.tap()
        from.typeText("2001")
        app.textFields["Year, to"].tap()
        app.textFields["Year, to"].typeText("2005")
        shot("4 Range filter")
        app.buttons["Apply"].tap()
        XCTAssertEqual(app.buttons["Filters"].value as? String, "On")
        XCTAssertTrue(app.button(containing: "Aidoku Sunrise").waitForExistence(timeout: 10), "The search with the range gives the list of the source.")
        app.buttons["Filters"].tap()
        XCTAssertEqual(app.textFields["Year, from"].value as? String, "2001", "The sheet keeps the applied range.")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
