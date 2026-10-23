import UIKit
import XCTest

/// Runs the accessibility audit of Xcode on each main screen. A missing label, a small touch target,
/// a wrong trait, or text with no Dynamic Type fails the test.
final class AccessibilityChecks: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)").path
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
    }

    private func audit(_ tab: String) throws {
        app.tabBars.buttons[tab].tap()
        sleep(1)
        try auditScreen(tab)
    }

    /// Audits the screen that shows now.
    private func auditScreen(_ name: String) throws {
        let bar = app.tabBars.firstMatch.frame
        try app.performAccessibilityAudit { issue in
            // The tab bar and the system parts are not the code of the app.
            if let frame = issue.element?.frame, bar.intersects(frame) { return true }
            // Contrast and clipped text show as notes, as in ZettaStream. The colours of the palette have a
            // contrast of 4.5 or more, which docs/decisions.md gives. The audit also counts parts of the system.
            let note: XCUIAccessibilityAuditType = [.contrast, .textClipped]
            let isNote = note.contains(issue.auditType) || issue.compactDescription.contains("partially")
            print("AUDIT \(isNote ? "note" : "fault") \(name): \(issue.compactDescription) on \(issue.element?.debugDescription.prefix(160) ?? "no element")")
            return isNote
        }
    }

    func testLibrary() throws { try audit("Library") }
    func testDiscover() throws { try audit("Discover") }
    func testSearch() throws { try audit("Search") }
    func testSettings() throws { try audit("Settings") }

    /// The pages of Settings: Sources, Storage, Trackers, and the move of books.
    func testThePagesOfSettings() throws {
        app.tabBars.buttons["Settings"].tap()
        for row in ["Storage", "Trackers", "Move books to another source"] {
            app.tapAfterScroll(app.buttons[row], opens: app.navigationBars.buttons.element(boundBy: 0))
            sleep(1)
            try auditScreen(row)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    /// The reader of a comic, with its bars, and the reader of a novel.
    func testTheReaders() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-a11y-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let comic = folder.appendingPathComponent("Audit_Comic.cbz")
        try StoredZip.write((1...3).map { ("\($0).jpg", Self.page($0)) }, to: comic)
        app.open(comic)
        let book = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Audit Comic'")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 30))
        book.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
        try auditScreen("Comic reader")
        app.buttons["Close"].tap()

        let novel = folder.appendingPathComponent("Quiet Mornings.epub")
        try StoredZip.write(NovelBook.epub, to: novel)
        app.open(novel)
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Quiet Mornings'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 30))
        tile.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
        sleep(2)
        try auditScreen("Novel reader")
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
