import XCTest

/// Pastes the real Aidoku Community list, and uses Discover and Search with its sources from the web.
/// It runs only with TEST_RUNNER_ASABUNKO_LIVE=1, because it needs the network and takes some minutes.
final class LiveSourcesTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["ASABUNKO_LIVE"] == "1" else { throw XCTSkip("ASABUNKO_LIVE is not 1.") }
        app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)").path
        app.launch()
    }

    /// MangaFire makes the key of each chapter in a web view, with `executeInWebView`.
    func testReadsAChapterOfMangaFire() throws {
        app.saveSourceLine("https://inkdex.github.io/extensions/0.9/stable/versioning.json")
        let installed = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Installed ('")).firstMatch
        XCTAssertTrue(installed.waitForExistence(timeout: 120), "The English extensions of Inkdex install.")
        // The list is long, so the row of MangaFire can be below the screen.
        let row = app.button(containing: "MangaFire")
        var swipes = 0
        while !(row.exists && row.isHittable) && swipes < 12 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(row.isHittable, "MangaFire is an English extension of the list.")
        row.tap()
        let titles = app.scrollViews.buttons.matching(NSPredicate(format: "NOT (label IN %@)", ["Popular", "Latest"]))
        XCTAssertTrue(titles.firstMatch.waitForExistence(timeout: 60), "MangaFire gives its popular titles.")
        // The list can open with an offset, so the test takes a title that is on the screen.
        let series = (0..<min(titles.count, 30)).map { titles.element(boundBy: $0) }.first { $0.isHittable }
        try XCTUnwrap(series, "A title is on the screen.").tap()
        let chapter = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Ch.'")).firstMatch
        // The chapters are under the facts of the title, in a list that loads its rows when they come on the screen.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Chapters '")).firstMatch.waitForExistence(timeout: 60)
                      || chapter.exists, "The title has chapters.")
        var scrolls = 0
        while !(chapter.exists && chapter.isHittable) && scrolls < 8 { app.swipeUp(); scrolls += 1 }
        XCTAssertTrue(chapter.isHittable, "A chapter is on the screen.")
        chapter.tap()
        let pages = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '1 of '")).firstMatch
        XCTAssertTrue(pages.waitForExistence(timeout: 90), "The pages of the chapter come from the key of the web view.")
        sleep(4)
        shot("10 MangaFire page")
    }

    func testSearchesAndDiscoversWithRealSources() throws {
        app.saveSourceLine("https://aidoku-community.github.io/sources/index.min.json")
        let installing = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Installing'")).firstMatch
        XCTAssertTrue(installing.waitForExistence(timeout: 30), "The sources of the list start to install.")
        shot("1 Sources install")
        let deadline = Date().addingTimeInterval(400)
        while installing.exists && Date() < deadline { sleep(3) }
        XCTAssertFalse(installing.exists, "All sources install.")
        shot("2 Installed sources")

        app.tabBars.buttons["Discover"].tap()
        XCTAssertTrue(app.buttons["Read"].waitForExistence(timeout: 90), "Discover shows a banner.")
        sleep(6)
        shot("3 Discover")
        app.swipeUp()
        sleep(2)
        shot("4 Discover rows")

        app.search("solo leveling")
        let title = app.button(containing: "sources")
        XCTAssertTrue(title.waitForExistence(timeout: 90), "Two or more sources have a title of the search.")
        sleep(8)
        shot("5 Search")
        title.tap()
        let source = app.buttons["Source"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        let chapters = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'chapters'")).firstMatch
        XCTAssertTrue(chapters.waitForExistence(timeout: 90), "The page compares the sources and shows the chapters.")
        shot("6 Title with the best source")
        source.tap()
        sleep(1)
        shot("7 Source menu")
        // A tap at the top closes the menu and chooses no source.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
        if app.buttons["Volumes"].waitForExistence(timeout: 2) {
            app.buttons["Volumes"].tap()
            sleep(1)
            shot("8 Volumes")
            app.buttons["Chapters"].tap()
        }
        app.swipeUp()
        sleep(1)
        shot("9 Chapter ranges")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
