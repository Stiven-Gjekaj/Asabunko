import UIKit
import XCTest

/// A book goes out with the share sheet into the Files app, and comes back from Files with the import.
final class FilesTests: XCTestCase {
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

    func testSharesABookToFilesAndOpensItFromFiles() throws {
        XCTAssertTrue(app.staticTexts["Your shelf is empty"].waitForExistence(timeout: 10))
        let source = folder.appendingPathComponent("Paper_Lantern.cbz")
        try StoredZip.write((1...3).map { ("\($0).jpg", Self.page($0)) }, to: source)
        app.open(source)
        let book = app.button(containing: "Paper Lantern")
        XCTAssertTrue(book.waitForExistence(timeout: 30))

        // The share sheet saves the CBZ of the book in Files, on the device.
        book.press(forDuration: 1.2)
        app.buttons["Share the file"].tap()
        let save = app.cells.matching(NSPredicate(format: "label CONTAINS 'Save to Files'")).firstMatch
        if !save.waitForExistence(timeout: 10) { app.swipeUp() }
        XCTAssertTrue(save.waitForExistence(timeout: 5), "The share sheet can save the file.")
        shot("1 Share sheet")
        save.tap()
        let device = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'On My'")).firstMatch
        if device.waitForExistence(timeout: 5) { device.tap() }
        let done = app.buttons["Save"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()
        // A file of an older run has the same name.
        let replace = app.buttons["Replace"]
        if replace.waitForExistence(timeout: 3) { replace.tap() }

        // The book leaves the library, and the import gets it back from Files.
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.press(forDuration: 1.2)
        app.buttons["Delete"].tap()
        app.buttons.matching(NSPredicate(format: "label == 'Delete'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Your shelf is empty"].waitForExistence(timeout: 10))
        app.buttons["Import"].tap()
        let browse = app.buttons["Browse"]
        if browse.waitForExistence(timeout: 5) { browse.tap() }
        if device.waitForExistence(timeout: 5) { device.tap() }
        let file = app.cells.matching(NSPredicate(format: "label CONTAINS 'Paper Lantern'")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10), "Files shows the saved book.")
        shot("2 Files")
        file.tap()
        if app.buttons["Open"].waitForExistence(timeout: 2) { app.buttons["Open"].tap() }
        XCTAssertTrue(book.waitForExistence(timeout: 30), "The book from Files is in the library.")
    }

    private static func page(_ number: Int) -> Data {
        let size = CGSize(width: 600, height: 900)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(hue: CGFloat(number) / 5, saturation: 0.4, brightness: 0.9, alpha: 1).setFill()
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
