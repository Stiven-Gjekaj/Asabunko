import UIKit
import XCTest

/// Imports a PDF that the test makes and turns its pages.
final class PDFTests: XCTestCase {
    private var app: XCUIApplication!
    private var book: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        book = folder.appendingPathComponent("Field_Guide.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 600))
        try renderer.writePDF(to: book) { context in
            for number in 1...3 {
                context.beginPage()
                ("Page \(number)" as NSString).draw(at: CGPoint(x: 120, y: 280), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 40)])
            }
        }
        app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = folder.appendingPathComponent("library").path
        app.launch()
    }

    func testImportsAndReadsAPDF() throws {
        XCTAssertTrue(app.staticTexts["Your shelf is empty"].waitForExistence(timeout: 10))
        app.open(book)
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Field Guide'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        tile.tap()
        XCTAssertTrue(app.staticTexts["1 of 3"].waitForExistence(timeout: 10))
        sleep(1)
        shot("1 PDF, first page")
        app.windows.firstMatch.swipeLeft()
        XCTAssertTrue(app.staticTexts["2 of 3"].waitForExistence(timeout: 5))
        app.buttons["Reading mode"].tap()
        app.buttons["Vertical scroll"].tap()
        sleep(1)
        shot("2 PDF, vertical")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Page 2 of 3"].waitForExistence(timeout: 5))
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
