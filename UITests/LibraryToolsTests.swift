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

    func testKeepsAHistoryExceptInPrivateReading() throws {
        XCTAssertTrue(app.staticTexts["Your shelf is empty"].waitForExistence(timeout: 10))
        try importBook("Harbor Lights")
        try importBook("Mountain Tea")
        app.button(containing: "Harbor Lights").tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
        app.buttons["Close"].tap()
        let history = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'History'")).firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 5), "The Library shows the history.")

        app.tabBars.buttons["Settings"].tap()
        let quiet = app.switches["Private reading"]
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
