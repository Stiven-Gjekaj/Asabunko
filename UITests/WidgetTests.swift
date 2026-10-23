import UIKit
import XCTest

/// Reads a book, then puts the Continue reading widget on the Home Screen. The widget shows the book.
final class WidgetTests: XCTestCase {
    func testShowsTheBookThatTheUserReadsInTheWidget() throws {
        continueAfterFailure = false
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = folder.appendingPathComponent("library").path
        app.launch()
        let file = folder.appendingPathComponent("Widget_Harbor.cbz")
        try StoredZip.write((1...3).map { ("\($0).jpg", Self.page($0)) }, to: file)
        app.open(file)
        let book = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Widget Harbor'")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 30))
        book.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
        app.buttons["Close"].tap()
        sleep(2)

        // The Home Screen: hold an empty place, then add the widget of Asabunko.
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let existing = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Widget Harbor'")).firstMatch
        if !existing.waitForExistence(timeout: 3) {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).press(forDuration: 1.5)
            // The edit button at the top left has only an icon.
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.19, dy: 0.037)).tap()
            let add = springboard.buttons.matching(NSPredicate(format: "label CONTAINS 'Add Widget'")).firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 5), "The Home Screen can add a widget.")
            add.tap()
            let entry = springboard.staticTexts["Asabunko"].firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 10), "The widget of Asabunko is in the gallery.")
            entry.tap()
            let confirm = springboard.buttons.matching(NSPredicate(format: "label CONTAINS 'Add Widget'")).firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 5))
            confirm.tap()
            sleep(3)
            XCUIDevice.shared.press(.home)
        }
        XCTAssertTrue(existing.waitForExistence(timeout: 15), "The widget shows the book.")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Widget"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func page(_ number: Int) -> Data {
        let size = CGSize(width: 600, height: 900)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(hue: CGFloat(number) / 6, saturation: 0.35, brightness: 0.9, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.7)!
    }
}
