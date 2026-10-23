import UIKit
import XCTest

/// The tools of the library: categories, the search and the filters, the history, the private reading,
/// the storage of the downloads, and the move of books to another source.
final class LibraryToolsTests: XCTestCase {
    private var app: XCUIApplication!
    private var folder: URL!
    private var server = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        server = ProcessInfo.processInfo.environment["SERVER_URL"] ?? ""
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = folder.appendingPathComponent("library").path
        app.launch()
    }

    /// A comic of two pages with the title in its file name.
    private func comic(_ name: String) throws -> URL {
        let url = folder.appendingPathComponent(name.replacingOccurrences(of: " ", with: "_") + ".cbz")
        try StoredZip.write((1...2).map { ("\($0).jpg", Self.page($0)) }, to: url)
        return url
    }

    private func importBook(_ name: String) throws {
        app.open(try comic(name))
        XCTAssertTrue(app.button(containing: name).waitForExistence(timeout: 30), "\(name) is in the library.")
    }

    func testSortsBooksIntoCategoriesAndFindsThem() throws {
        XCTAssertTrue(app.staticTexts["Your shelf is empty"].waitForExistence(timeout: 10))
        try importBook("Harbor Lights")
        try importBook("Mountain Tea")

        // A category, and a book in it.
        app.buttons["Add a category"].tap()
        let field = app.textFields["New category"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Reading\n")
        app.buttons["Done"].tap()
        app.button(containing: "Mountain Tea").press(forDuration: 1.2)
        app.buttons["Categories"].tap()
        // The chip of the category is behind the menu. The item of the menu is the wide one.
        let items = app.buttons.matching(NSPredicate(format: "label == 'Reading'"))
        XCTAssertTrue(items.firstMatch.waitForExistence(timeout: 5))
        let item = (0..<items.count).map { items.element(boundBy: $0) }.max { $0.frame.width < $1.frame.width }
        try XCTUnwrap(item).tap()
        let chip = app.buttons.matching(NSPredicate(format: "label == 'Reading'")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        XCTAssertTrue(app.button(containing: "Mountain Tea").waitForExistence(timeout: 5))
        XCTAssertFalse(app.button(containing: "Harbor Lights").exists, "The category shows only its books.")
        shot("1 Category")
        app.buttons.matching(NSPredicate(format: "label == 'All'")).firstMatch.tap()

        // The search of the library.
        app.swipeDown()
        let search = app.searchFields["Search the library"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("harbor")
        XCTAssertTrue(app.button(containing: "Harbor Lights").waitForExistence(timeout: 5))
        XCTAssertFalse(app.button(containing: "Mountain Tea").exists, "The search keeps the books with the words.")
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "harbor".count))
        XCTAssertTrue(app.button(containing: "Mountain Tea").waitForExistence(timeout: 5), "An empty search shows all books.")

        // A filter: the imported books are comics, so the filter of novels shows none.
        app.buttons["Filter the read list"].tap()
        app.buttons["Novels"].tap()
        XCTAssertTrue(app.staticTexts["No book of the read list fits the filters."].waitForExistence(timeout: 5))
    }

    func testKeepsAHistoryExceptInPrivateReading() throws {
        XCTAssertTrue(app.staticTexts["Your shelf is empty"].waitForExistence(timeout: 10))
        // The settings of the simulator stay after a test, so an older run can leave the private reading on.
        app.tabBars.buttons["Settings"].tap()
        let quiet = app.switches["Private reading"]
        app.reveal(quiet)
        if quiet.value as? String == "1" { quiet.switches.firstMatch.tap() }
        app.tabBars.buttons["Library"].tap()
        try importBook("Harbor Lights")
        try importBook("Mountain Tea")
        app.button(containing: "Harbor Lights").tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
        app.buttons["Close"].tap()
        let history = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'History'")).firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 5), "The Library shows the history.")

        app.tabBars.buttons["Settings"].tap()
        app.reveal(quiet)
        quiet.switches.firstMatch.tap()
        app.tabBars.buttons["Library"].tap()
        app.button(containing: "Mountain Tea").tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
        app.buttons["Close"].tap()

        history.tap()
        XCTAssertTrue(app.button(containing: "Harbor Lights").waitForExistence(timeout: 5))
        XCTAssertFalse(app.button(containing: "Mountain Tea").exists, "A book of the private reading is not in the history.")
        shot("2 History")
        // The next test starts with the private reading off.
        app.tabBars.buttons["Settings"].tap()
        app.reveal(quiet)
        quiet.switches.firstMatch.tap()
    }

    func testMovesABookAndRemovesItsDownloads() throws {
        guard !server.isEmpty else { throw XCTSkip("SERVER_URL is not set.") }
        app.saveSourceLine(server + "/aidoku/index.min.json\n" + server + "/paperback/versioning.json")
        app.waitForInstalled(2)
        app.search("sunrise")
        let series = app.button(containing: "Aidoku Sunrise")
        XCTAssertTrue(series.waitForExistence(timeout: 15))
        series.tap()
        XCTAssertTrue(app.buttons["Add to the read list"].waitForExistence(timeout: 10))
        app.buttons["Add to the read list"].tap()
        app.buttons["Downloads"].tap()
        app.buttons["Download all chapters"].tap()
        XCTAssertTrue(app.images["Downloaded"].waitForExistence(timeout: 20))

        // The storage shows the download, and removes it.
        app.tabBars.buttons["Settings"].tap()
        // The Settings tab still shows the Sources page from the start of the test.
        if app.navigationBars["Sources"].exists { app.navigationBars.buttons.element(boundBy: 0).tap() }
        app.tapAfterScroll(app.buttons["Storage"], opens: app.staticTexts["1 chapters on the device"])
        XCTAssertTrue(app.staticTexts["1 chapters on the device"].waitForExistence(timeout: 10), "The storage shows the book with its download.")
        shot("3 Storage")
        app.buttons["Remove all downloads"].tap()
        app.buttons["Remove all"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No downloads"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // The book moves to the Paperback source, which has the same title.
        app.tapAfterScroll(app.buttons["Move books to another source"], opens: app.button(containing: "Aidoku Sunrise"))
        app.button(containing: "Aidoku Sunrise").tap()
        // The label of a picker holds its value too.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Source'")).firstMatch.tap()
        app.buttons["Quiet Paper"].tap()
        // A tap while the menu closes does nothing, so the test waits for the value of the picker.
        let picked = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Source' AND label CONTAINS 'Quiet Paper'")).firstMatch
        XCTAssertTrue(picked.waitForExistence(timeout: 5))
        let find = app.buttons["Find the titles"]
        find.tap()
        if !app.buttons["Move 1 book"].waitForExistence(timeout: 5) { find.tap() }
        let move = app.buttons["Move 1 book"]
        XCTAssertTrue(move.waitForExistence(timeout: 15), "The new source has the title.")
        shot("4 Matches")
        move.tap()
        XCTAssertTrue(app.staticTexts["1 book moved."].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tapAfterScroll(app.buttons["Move books to another source"], opens: app.button(containing: "Aidoku Sunrise"))
        XCTAssertTrue(app.button(containing: "Quiet Paper").waitForExistence(timeout: 5), "The book reads from the new source.")
    }

    private static func page(_ number: Int) -> Data {
        let size = CGSize(width: 600, height: 900)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(hue: CGFloat(number) / 5, saturation: 0.3, brightness: 0.9, alpha: 1).setFill()
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
