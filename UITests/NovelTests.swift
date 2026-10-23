import XCTest

/// Imports an EPUB that the test makes and reads it.
final class NovelTests: XCTestCase {
    private var app: XCUIApplication!
    private var book: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        book = folder.appendingPathComponent("Quiet_Mornings.epub")
        try StoredZip.write(NovelBook.epub, to: book)
        app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = folder.appendingPathComponent("library").path
        app.launch()
    }

    func testImportsAndReadsAnEPUB() throws {
        XCTAssertTrue(app.staticTexts["Your shelf is empty"].waitForExistence(timeout: 10))
        app.open(book)
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Quiet Mornings'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        tile.tap()

        XCTAssertTrue(app.staticTexts["Chapter 1 of 3"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS 'The kettle sang'")).firstMatch.waitForExistence(timeout: 10))
        shot("1 Novel, first chapter")

        app.buttons["Next chapter"].tap()
        XCTAssertTrue(app.staticTexts["Chapter 2 of 3"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS 'rain on the window'")).firstMatch.waitForExistence(timeout: 10))

        app.buttons["Chapters"].tap()
        XCTAssertTrue(app.buttons["Evening Bells"].waitForExistence(timeout: 5))
        shot("2 Chapter list")
        app.buttons["Evening Bells"].tap()
        XCTAssertTrue(app.staticTexts["Chapter 3 of 3"].waitForExistence(timeout: 5))

        app.buttons["Text settings"].tap()
        XCTAssertTrue(app.staticTexts["Size"].waitForExistence(timeout: 5))
        app.steppers.firstMatch.buttons["Increment"].tap()
        app.steppers.firstMatch.buttons["Increment"].tap()
        shot("3 Text settings")
        app.buttons["Done"].tap()
        sleep(1)
        shot("4 Novel, larger text")

        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Chapter 3 of 3"].waitForExistence(timeout: 5), "Continue reading shows the chapter.")
        shot("5 Library with a novel")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
