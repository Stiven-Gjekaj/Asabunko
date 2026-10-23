import XCTest

/// Saves a backup in the Files app, clears the source list, and restores the backup from Files.
final class BackupTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)").path
        app.launch()
    }

    func testSavesAndRestoresABackupWithTheFilesApp() throws {
        // A catalog line has no sources to install, so the test needs no server.
        let line = "https://backup-\(UUID().uuidString.prefix(6).lowercased()).test/opds/v1.2/catalog"
        app.saveSourceLine(line)
        let host = URL(string: line)!.host!
        let row = app.button(containing: host)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // The name of the backup has the local time, so the test knows the start of the name.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        let saved = Date()
        let names = [saved, saved.addingTimeInterval(60)].map { "Asabunko " + formatter.string(from: $0) }
        app.reveal(app.buttons["Save a backup"])
        app.buttons["Save a backup"].tap()
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "The Files picker opens.")
        shot("1 Save the backup")
        save.tap()
        // The picker closes when the file is saved.
        let deadline = Date().addingTimeInterval(15)
        while save.exists && Date() < deadline { sleep(1) }
        XCTAssertTrue(app.buttons["Save a backup"].waitForExistence(timeout: 10))

        // The list is empty now.
        let sources = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sources'")).firstMatch
        app.tapAfterScroll(sources, opens: app.buttons["Edit the source list"])
        app.buttons["Edit the source list"].tap()
        let box = app.textViews["Source list"]
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        box.tap()
        box.press(forDuration: 1.2)
        if app.menuItems["Select All"].waitForExistence(timeout: 3) { app.menuItems["Select All"].tap() }
        box.typeText(XCUIKeyboardKey.delete.rawValue)
        app.buttons["Save"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertFalse(row.exists, "The line is gone.")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.reveal(app.buttons["Restore a backup"])
        app.buttons["Restore a backup"].tap()
        // The name of a backup has the date and the time. A cell named only "Asabunko" is the folder of the app.
        let files = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", names[0], names[1]))
        if !files.firstMatch.waitForExistence(timeout: 5) {
            app.cells.matching(NSPredicate(format: "label BEGINSWITH 'Asabunko'")).firstMatch.tap()
        }
        XCTAssertTrue(files.firstMatch.waitForExistence(timeout: 10), "The picker shows the backup.")
        shot("2 Choose the backup")
        // Only the backup of this test has this name.
        files.firstMatch.tap()
        // The dialog comes with an animation, and a tap during it does nothing, so the test taps again.
        let dialog = app.sheets["Restore the backup?"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 10))
        var tries = 0
        while dialog.exists && tries < 5 {
            sleep(1)
            if dialog.buttons["Restore"].exists { dialog.buttons["Restore"].tap() }
            tries += 1
        }
        XCTAssertTrue(app.staticTexts["The backup is restored."].waitForExistence(timeout: 10))
        app.buttons["OK"].tap()

        app.tapAfterScroll(sources, opens: app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Edit the source list' OR label BEGINSWITH 'Add sources'")).firstMatch)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The line of the backup is back.")
        shot("3 Restored source list")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
