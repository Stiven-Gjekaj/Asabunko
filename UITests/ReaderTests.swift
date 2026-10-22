import UIKit
import XCTest

/// Imports a CBZ that the test makes, reads it, and changes the look.
/// Each test starts with an empty library in a new folder.
final class ReaderTests: XCTestCase {
    private var app: XCUIApplication!
    private var book: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        book = folder.appendingPathComponent("Morning_Shelf_v01.cbz")
        var files = (1...5).map { ("page \($0).png", Self.page($0)) }
        files.append(("ComicInfo.xml", Data("""
        <?xml version="1.0"?><ComicInfo><Series>Morning Shelf</Series><Number>1</Number>\
        <Title>A Sample</Title><Manga>YesAndRightToLeft</Manga></ComicInfo>
        """.utf8)))
        files.shuffle()
        try StoredZip.write(files, to: book)

        app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = folder.appendingPathComponent("library").path
        app.launch()
    }

    func testImportsAndReadsAMangaFromTheRightToTheLeft() throws {
        XCTAssertTrue(app.staticTexts["Your shelf is empty"].waitForExistence(timeout: 10))
        shot("1 Empty library")

        app.open(book)
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Morning Shelf 1: A Sample'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 15), "The imported book is in the library.")
        shot("2 Library with one book")

        tile.tap()
        XCTAssertTrue(app.staticTexts["1 of 5"].waitForExistence(timeout: 10))
        shot("3 Reader, first page")

        // In a manga the right edge goes back, so the reader stays on the first page.
        tapAt(x: 0.9)
        XCTAssertTrue(app.staticTexts["1 of 5"].waitForExistence(timeout: 3))
        tapAt(x: 0.1)
        XCTAssertTrue(app.staticTexts["2 of 5"].waitForExistence(timeout: 5))
        tapAt(x: 0.1)
        XCTAssertTrue(app.staticTexts["3 of 5"].waitForExistence(timeout: 5))
        shot("4 Reader, third page")

        // The middle hides the bars and shows them again.
        tapAt(x: 0.5)
        XCTAssertTrue(app.staticTexts["3 of 5"].waitForNonExistence(timeout: 3))
        shot("5 Reader with no bars")
        tapAt(x: 0.5)
        XCTAssertTrue(app.staticTexts["3 of 5"].waitForExistence(timeout: 3))

        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Continue reading"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Page 3 of 5"].exists)
        shot("6 Library with continue reading")

        tile.tap()
        XCTAssertTrue(app.staticTexts["3 of 5"].waitForExistence(timeout: 10), "The reader opens at the saved page.")
        app.buttons["Reading mode"].tap()
        app.buttons["Vertical scroll"].tap()
        sleep(1)
        shot("7 Vertical reader")
        app.buttons["Close"].tap()
    }

    func testChangesTheAppearance() throws {
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Appearance'")).firstMatch.tap()
        app.buttons["Warm dark"].tap()
        sleep(1)
        shot("8 Settings, warm dark")
        app.buttons["Done"].tap()
        sleep(1)
        shot("9 Empty library, warm dark")
        app.buttons["Settings"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Appearance'")).firstMatch.tap()
        app.buttons["Same as the device"].tap()
    }

    private func tapAt(x: CGFloat) {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)).tap()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A page with its number, so that a screenshot shows which page is open.
    private static func page(_ number: Int) -> Data {
        let size = CGSize(width: 800, height: 1200)
        return UIGraphicsImageRenderer(size: size).pngData { context in
            UIColor(hue: CGFloat(number) / 6, saturation: 0.3, brightness: 0.9, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let text = "\(number)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 300), .foregroundColor: UIColor.darkGray]
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2), withAttributes: attributes)
        }
    }
}
