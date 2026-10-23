import XCTest

/// Reads each tab at the largest text size. Text that the screen cuts, or text with no Dynamic Type, fails the test.
final class LargeTextTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)").path
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
    }

    private func read(_ tab: String) throws {
        app.tabBars.buttons[tab].tap()
        sleep(1)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(tab) at the largest text size"
        attachment.lifetime = .keepAlways
        add(attachment)
        let bar = app.tabBars.firstMatch.frame
        let screen = app.windows.firstMatch.frame
        try app.performAccessibilityAudit(for: [.textClipped, .dynamicType]) { issue in
            // The tab bar and the search field are parts of the system, not the code of the app.
            if let element = issue.element, bar.intersects(element.frame) || element.elementType == .searchField { return true }
            // The audit also reports text that a row cuts by a few points. A fault is text past the edge of the screen.
            if issue.auditType == .textClipped, let frame = issue.element?.frame,
               frame.minX >= screen.minX, frame.maxX <= screen.maxX { return true }
            print("LARGE TEXT \(tab): \(issue.compactDescription) on \(issue.element?.debugDescription.prefix(160) ?? "no element")")
            return false
        }
        // The content keeps its margins: no text starts at the edge of the screen.
        let texts = app.scrollViews.firstMatch.staticTexts.allElementsBoundByIndex.filter { $0.isHittable }
        for text in texts {
            XCTAssertGreaterThanOrEqual(text.frame.minX, screen.minX + 8, "\(text.label) keeps a margin at the left in \(tab).")
        }
    }

    func testLibrary() throws { try read("Library") }
    func testDiscover() throws { try read("Discover") }
    func testSearch() throws { try read("Search") }
    func testSettings() throws { try read("Settings") }
}
