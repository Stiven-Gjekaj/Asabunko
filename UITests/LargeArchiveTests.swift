import UIKit
import XCTest

/// Imports a CBZ of 600 pages that the test makes, and reads its last pages.
final class LargeArchiveTests: XCTestCase {
    private var app: XCUIApplication!
    private var book: URL!
    private let count = 600

    override func setUpWithError() throws {
        continueAfterFailure = false
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        book = folder.appendingPathComponent("Long_Road.cbz")
        // The pages have the size of a page of a phone scan, and their names have no zeros in front.
        try StoredZip.write((1...count).map { ("\($0).jpg", Self.page($0)) }, to: book)
        app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = folder.appendingPathComponent("library").path
        app.launch()
    }

    func testImportsAndReadsAnArchiveOf600Pages() throws {
        XCTAssertTrue(app.staticTexts["Your shelf is empty"].waitForExistence(timeout: 10))
        let start = Date()
        app.open(book)
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Long Road'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 120), "The import of 600 pages ends.")
        print("LARGE import of \(count) pages: \(String(format: "%.1f", Date().timeIntervalSince(start))) s")
        tile.tap()
        XCTAssertTrue(app.staticTexts["1 of \(count)"].waitForExistence(timeout: 15))

        // In the first mode, a manga, the slider starts at the right. From the left to the right, its end is the last page.
        app.buttons["Reading mode"].tap()
        app.buttons["Left to right"].tap()
        app.sliders["Page"].adjust(toNormalizedSliderPosition: 1)
        // On a slider of 600 steps, one point is more than one page, so the slider stops near the end.
        let near = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'of \(count)'")).firstMatch
        XCTAssertTrue(near.waitForExistence(timeout: 5))
        let reached = Int(near.label.split(separator: " ").first ?? "") ?? 0
        XCTAssertGreaterThan(reached, count - 20, "The slider goes near the last page.")
        // The right edge turns the pages to the end.
        var taps = 0
        while !app.staticTexts["\(count) of \(count)"].exists && taps < 30 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            taps += 1
            // Two quick taps are a double tap, which zooms the page.
            usleep(600_000)
        }
        XCTAssertTrue(app.staticTexts["\(count) of \(count)"].waitForExistence(timeout: 5), "The last page is the page 600 in natural order.")
        let last = app.images["Page \(count)"]
        let deadline = Date().addingTimeInterval(10)
        while last.value as? String != "Loaded" && Date() < deadline { sleep(1) }
        XCTAssertEqual(last.value as? String, "Loaded")
        shot("1 Last page of 600")

        app.sliders["Page"].adjust(toNormalizedSliderPosition: 0.5)
        sleep(1)
        let middle = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'of \(count)'")).firstMatch
        XCTAssertTrue(middle.exists)
        shot("2 Middle page")
        app.buttons["Close"].tap()
    }

    private static func page(_ number: Int) -> Data {
        let size = CGSize(width: 1080, height: 1620)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(hue: CGFloat(number % 12) / 12, saturation: 0.25, brightness: 0.95, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let text = "\(number)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 260), .foregroundColor: UIColor.darkGray]
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2), withAttributes: attributes)
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
