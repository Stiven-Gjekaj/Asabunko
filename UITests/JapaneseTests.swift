import XCTest

/// The app in Japanese: the tabs, the Library, and Settings show the text of the catalog.
final class JapaneseTests: XCTestCase {
    func testShowsEachTabInJapanese() throws {
        continueAfterFailure = false
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)")
        let app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = folder.path
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        XCTAssertTrue(app.staticTexts["ライブラリ"].waitForExistence(timeout: 10), "The Library has its Japanese title.")
        for tab in ["発見", "検索", "設定", "ライブラリ"] {
            XCTAssertTrue(app.tabBars.buttons[tab].exists, "The tab \(tab) is in Japanese.")
        }
        app.tabBars.buttons["設定"].tap()
        let look = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '外観'")).firstMatch
        XCTAssertTrue(look.waitForExistence(timeout: 5), "Settings is in Japanese.")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Settings in Japanese"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
