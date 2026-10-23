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

    /// Scrolls until the element is on the screen. A list loads its rows only when they come near the screen.
    func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for up in [true, false] {
            for _ in 0..<8 where !(element.exists && element.isHittable) {
                if up { swipeUp() } else { swipeDown() }
            }
        }
        XCTAssertTrue(element.exists && element.isHittable, "The element is on the screen.", file: file, line: line)
    }

    /// Taps a row of a list after a scroll. A tap while the list still moves only stops the list, so the
    /// tap goes again when the next screen did not open.
    func tapAfterScroll(_ element: XCUIElement, opens next: XCUIElement) {
        reveal(element)
        element.tap()
        if !next.waitForExistence(timeout: 3) { element.tap() }
        XCTAssertTrue(next.waitForExistence(timeout: 5), "The row opens its screen.")
    }

    /// A button with a label that holds the text.
    func button(containing text: String) -> XCUIElement {
        buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
