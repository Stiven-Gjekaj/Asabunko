import XCTest

/// The steps that many tests share: the source list in Settings, and the search.
extension XCUIApplication {
    /// Opens Settings, Sources, and saves one line in the source list. The Sources page stays open.
    func saveSourceLine(_ line: String) {
        tabBars.buttons["Settings"].tap()
        let sources = buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sources'")).firstMatch
        XCTAssertTrue(sources.waitForExistence(timeout: 5))
        sources.tap()
        buttons["Add sources"].tap()
        let box = textViews["Source list"]
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        box.tap()
        box.typeText(line)
        buttons["Save"].tap()
        navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// Waits until the Sources page shows the number of installed sources.
    func waitForInstalled(_ count: Int, file: StaticString = #filePath, line: UInt = #line) {
        let header = staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Installed (\(count))")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 20), "The sources of the list install with no question.", file: file, line: line)
    }

    /// Searches all sources in the Search tab.
    func search(_ text: String) {
        tabBars.buttons["Search"].tap()
        let field = textFields["Search titles"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text + "\n")
    }

    /// A button with a label that holds the text.
    func button(containing text: String) -> XCUIElement {
        buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
