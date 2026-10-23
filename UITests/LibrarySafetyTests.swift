import XCTest

/// Starts the app with a library file that it cannot read. The app must not write over the file.
final class LibrarySafetyTests: XCTestCase {
    func testKeepsALibraryFileThatDoesNotLoad() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("library.json")
        let broken = Data(#"{"form":1,"books":[{"id":"not a book"}],"defaultMode":"rightToLeft"}"#.utf8)
        try broken.write(to: file)

        let app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = folder.path
        app.launch()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS 'cannot be read'")).firstMatch.exists)
        alert.buttons["OK"].tap()

        // A change of the reading mode saves the library in a normal case.
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Start a new library"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reading mode'")).firstMatch.tap()
        app.buttons["Vertical scroll"].tap()
        sleep(2)
        XCTAssertEqual(try Data(contentsOf: file), broken, "The file stays as it was.")
        let copies = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("library.broken-") }
        XCTAssertEqual(copies.count, 1, "A copy of the file is next to it.")

        app.buttons["Start a new library"].tap()
        app.buttons.matching(NSPredicate(format: "label == 'Start a new library'")).element(boundBy: 1).tap()
        sleep(2)
        XCTAssertNotEqual(try Data(contentsOf: file), broken, "A new library writes the file.")
        XCTAssertFalse(app.buttons["Start a new library"].exists)
    }
}
