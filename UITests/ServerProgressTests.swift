import XCTest

/// A comic of a Komga server opens at the page that the server keeps, and each new page goes back to the server.
/// The test server acts as Komga.
final class ServerProgressTests: XCTestCase {
    private var app: XCUIApplication!
    private var server = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        server = ProcessInfo.processInfo.environment["SERVER_URL"] ?? ""
        guard !server.isEmpty else { throw XCTSkip("SERVER_URL is not set.") }
        _ = try? Data(contentsOf: URL(string: server + "/control/reset")!)
        // The user read to page 3 on another device.
        _ = try? Data(contentsOf: URL(string: server + "/control/komga?page=3")!)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)")
        app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = folder.appendingPathComponent("library").path
        app.launch()
    }

    func testOpensAtThePageOfKomgaAndSendsTheNextPage() throws {
        app.saveSourceLine(server.replacingOccurrences(of: "http://", with: "http://asa:morning@") + "/komga/opds/v1.2/catalog")
        app.buttons.matching(NSPredicate(format: "label CONTAINS '127.0.0.1'")).firstMatch.tap()
        let book = app.button(containing: "Komga Dawn")
        XCTAssertTrue(book.waitForExistence(timeout: 10), "The catalog opens with the password.")
        book.tap()
        app.buttons["Read now"].tap()
        XCTAssertTrue(app.staticTexts["3 of 4"].waitForExistence(timeout: 10), "The stream opens at the page of the server.")
        shot("1 Page of the server")

        // A turn to the last page finishes the book on the server.
        // A manga goes forward with a swipe to the right. When the swipe went back, two swipes to the left go forward.
        app.swipeRight()
        if !app.staticTexts["4 of 4"].waitForExistence(timeout: 3) { app.swipeLeft(); app.swipeLeft() }
        XCTAssertTrue(app.staticTexts["4 of 4"].waitForExistence(timeout: 5))
        let state = URL(string: server + "/komga/state")!
        var progress: [String: Any] = [:]
        for _ in 0..<20 {
            if let data = try? Data(contentsOf: state), let read = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { progress = read }
            if progress["page"] as? Int == 4 { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertEqual(progress["page"] as? Int, 4, "Komga gets the new page, from 1.")
        XCTAssertEqual(progress["completed"] as? Bool, true)
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
