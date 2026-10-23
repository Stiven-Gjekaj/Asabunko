import UIKit
import XCTest

/// Takes a screenshot of each tab and of the reader with a book in the library. Run it on an iPad to check
/// the look of the wide screens.
final class LayoutTests: XCTestCase {
    func testShowsEachTabWithABook() throws {
        continueAfterFailure = true
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = folder.appendingPathComponent("library").path
        app.launch()
        let file = folder.appendingPathComponent("Wide_Harbor.cbz")
        try StoredZip.write((1...4).map { ("\($0).jpg", Self.page($0)) }, to: file)
        app.open(file)
        let book = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Wide Harbor'")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 30))
        for tab in ["Library", "Discover", "Search", "Settings"] {
            // An iPad shows the tabs at the top, not in a tab bar.
            app.buttons[tab].firstMatch.tap()
            sleep(1)
            shot(app, tab)
        }
        app.buttons["Library"].firstMatch.tap()
        book.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(4)
        shot(app, "Reader in landscape")
        // The cover is alone in its spread, at the middle of the screen.
        let cover = app.images["Page 1"], screen = app.windows.firstMatch.frame
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertEqual(cover.frame.midX, screen.midX, accuracy: 4, "The cover is at the middle of the wide screen.")
        XCTAssertGreaterThan(screen.width, screen.height, "The window turned to landscape.")
        XCUIDevice.shared.orientation = .portrait
    }

    private static func page(_ number: Int) -> Data {
        let size = CGSize(width: 600, height: 900)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(hue: CGFloat(number) / 6, saturation: 0.35, brightness: 0.9, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.7)!
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
