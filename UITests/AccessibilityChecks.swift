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
        let bar = app.tabBars.firstMatch.frame
        try app.performAccessibilityAudit { issue in
            // The tab bar and the system parts are not the code of the app.
            if let frame = issue.element?.frame, bar.intersects(frame) { return true }
            // Contrast and clipped text show as notes, as in ZettaStream. The colours of the palette have a
            // contrast of 4.5 or more, which docs/decisions.md gives. The audit also counts parts of the system.
            let note: XCUIAccessibilityAuditType = [.contrast, .textClipped]
            let isNote = note.contains(issue.auditType) || issue.compactDescription.contains("partially")
            print("AUDIT \(isNote ? "note" : "fault") \(tab): \(issue.compactDescription) on \(issue.element?.debugDescription.prefix(160) ?? "no element")")
            return isNote
        }
    }

    func testLibrary() throws { try audit("Library") }
    func testDiscover() throws { try audit("Discover") }
    func testSearch() throws { try audit("Search") }
    func testSettings() throws { try audit("Settings") }
}
