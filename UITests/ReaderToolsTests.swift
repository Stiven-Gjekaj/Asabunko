import UIKit
import XCTest

/// The tools of the readers: two pages in landscape, the fit, the taps, and in a novel the speech, the search,
/// and the marks.
final class ReaderToolsTests: XCTestCase {
    private var app: XCUIApplication!
    private var folder: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = folder.appendingPathComponent("library").path
        app.launch()
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    func testShowsTwoPagesInLandscapeAndChangesTheFitAndTheTaps() throws {
        let book = folder.appendingPathComponent("Wide_Bay.cbz")
        try StoredZip.write((1...6).map { ("\($0).jpg", Self.page($0)) }, to: book)
        XCTAssertTrue(app.staticTexts["Your shelf is empty"].waitForExistence(timeout: 10))
        app.open(book)
        let tile = app.button(containing: "Wide Bay")
        XCTAssertTrue(tile.waitForExistence(timeout: 30))
        tile.tap()
        XCTAssertTrue(app.staticTexts["1 of 6"].waitForExistence(timeout: 10))
        app.buttons["Reading mode"].tap()
        app.buttons["Left to right"].tap()

        // The taps: forward at each edge, so a tap at the left edge goes forward.
        // A tap while the menu of the mode closes does nothing, so the test waits for the menu to close.
        // The pickers of the menu show their choices in the menu.
        let forward = app.buttons["Forward at each edge"]
        sleep(1)
        app.buttons["Page layout"].tap()
        if !forward.waitForExistence(timeout: 3) { app.buttons["Page layout"].tap() }
        app.buttons["Forward at each edge"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["2 of 6"].waitForExistence(timeout: 5), "A tap at the left edge goes forward.")
        // The bars hid with the turn. A tap in the middle shows them.
        if !app.buttons["Page layout"].exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }

        // In landscape the pages 2 and 3 show side by side, after the cover.
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.staticTexts["2-3 of 6"].waitForExistence(timeout: 10), "Two pages show on a wide screen.")
        XCTAssertTrue(app.images["Page 2"].exists && app.images["Page 3"].exists)
        let left = app.images["Page 2"].frame, right = app.images["Page 3"].frame
        XCTAssertLessThan(left.midX, right.midX, "From the left to the right, the first page is at the left.")
        shot("1 Two pages")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.staticTexts["2 of 6"].waitForExistence(timeout: 10))

        // The fit of the width: the page is as wide as the screen.
        if !app.buttons["Page layout"].exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        app.buttons["Page layout"].tap()
        app.buttons["Fit the width"].tap()
        let image = app.images["Page 2"]
        let screen = app.windows.firstMatch.frame
        let wide = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(image.frame.width - screen.width) < 2 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [wide], timeout: 5), .completed, "The page fills the width of the screen.")
    }

    func testReadsANovelAloudSearchesItAndKeepsABookmark() throws {
        let book = folder.appendingPathComponent("Quiet_Mornings.epub")
        try StoredZip.write(NovelBook.epub, to: book)
        XCTAssertTrue(app.staticTexts["Your shelf is empty"].waitForExistence(timeout: 10))
        app.open(book)
        let tile = app.button(containing: "Quiet Mornings")
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        tile.tap()
        XCTAssertTrue(app.staticTexts["Chapter 1 of 3"].waitForExistence(timeout: 10))

        // The speech goes from one sentence to the next.
        app.buttons["Read aloud"].tap()
        let stop = app.buttons["Stop reading aloud"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "The speech starts.")
        let next = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH 'Sentence 2 of'"), object: stop)
        XCTAssertEqual(XCTWaiter.wait(for: [next], timeout: 30), .completed, "The reader goes to the next sentence.")
        shot("2 Read aloud")
        stop.tap()

        // The search finds words of the second chapter.
        app.buttons["Search the book"].tap()
        let field = app.searchFields["Words in the book"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("rain on")
        let result = app.button(containing: "Soft Rain")
        XCTAssertTrue(result.waitForExistence(timeout: 5), "The search finds the chapter.")
        result.tap()
        XCTAssertTrue(app.staticTexts["Chapter 2 of 3"].waitForExistence(timeout: 10))

        // A bookmark stays in the list of the marks.
        app.buttons["Marks"].tap()
        app.buttons["Add a bookmark here"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Bookmark:'")).firstMatch.waitForExistence(timeout: 5))
        shot("3 Marks")
    }

    private static func page(_ number: Int) -> Data {
        let size = CGSize(width: 600, height: 900)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(hue: CGFloat(number) / 7, saturation: 0.3, brightness: 0.9, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.7)!
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
