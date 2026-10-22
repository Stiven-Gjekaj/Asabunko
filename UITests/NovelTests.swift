import XCTest

/// Imports an EPUB that the test makes and reads it.
final class NovelTests: XCTestCase {
    private var app: XCUIApplication!
    private var book: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        book = folder.appendingPathComponent("Quiet_Mornings.epub")
        try StoredZip.write(Self.epub, to: book)
        app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = folder.appendingPathComponent("library").path
        app.launch()
    }

    func testImportsAndReadsAnEPUB() throws {
        XCTAssertTrue(app.staticTexts["Your shelf is empty"].waitForExistence(timeout: 10))
        app.open(book)
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Quiet Mornings'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        tile.tap()

        XCTAssertTrue(app.staticTexts["Chapter 1 of 3"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS 'The kettle sang'")).firstMatch.waitForExistence(timeout: 10))
        shot("1 Novel, first chapter")

        app.buttons["Next chapter"].tap()
        XCTAssertTrue(app.staticTexts["Chapter 2 of 3"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS 'rain on the window'")).firstMatch.waitForExistence(timeout: 10))

        app.buttons["Chapters"].tap()
        XCTAssertTrue(app.buttons["Evening Bells"].waitForExistence(timeout: 5))
        shot("2 Chapter list")
        app.buttons["Evening Bells"].tap()
        XCTAssertTrue(app.staticTexts["Chapter 3 of 3"].waitForExistence(timeout: 5))

        app.buttons["Text settings"].tap()
        XCTAssertTrue(app.staticTexts["Size"].waitForExistence(timeout: 5))
        app.steppers.firstMatch.buttons["Increment"].tap()
        app.steppers.firstMatch.buttons["Increment"].tap()
        shot("3 Text settings")
        app.buttons["Done"].tap()
        sleep(1)
        shot("4 Novel, larger text")

        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Chapter 3 of 3"].waitForExistence(timeout: 5), "Continue reading shows the chapter.")
        shot("5 Library with a novel")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func page(_ title: String, _ text: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>\(title)</title>
        <script>document.body.innerHTML = 'SCRIPT RAN';</script></head>
        <body><h2>\(title)</h2><p>\(text)</p><p>\(String(repeating: "A quiet line of the morning. ", count: 60))</p></body></html>
        """.utf8)
    }

    private static var epub: [(String, Data)] {
        [
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data("""
            <?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
            <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
            """.utf8)),
            ("OEBPS/content.opf", Data("""
            <?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0">
            <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Quiet Mornings</dc:title><dc:creator>Asa Writer</dc:creator></metadata>
            <manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="a" href="a.xhtml" media-type="application/xhtml+xml"/><item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>
            <item id="c" href="c.xhtml" media-type="application/xhtml+xml"/></manifest>
            <spine><itemref idref="a"/><itemref idref="b"/><itemref idref="c"/></spine></package>
            """.utf8)),
            ("OEBPS/nav.xhtml", Data("""
            <?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
            <nav epub:type="toc"><ol><li><a href="a.xhtml">First Light</a></li><li><a href="b.xhtml">Soft Rain</a></li>
            <li><a href="c.xhtml">Evening Bells</a></li></ol></nav></body></html>
            """.utf8)),
            ("OEBPS/a.xhtml", page("First Light", "The kettle sang in the small kitchen.")),
            ("OEBPS/b.xhtml", page("Soft Rain", "There was rain on the window all day.")),
            ("OEBPS/c.xhtml", page("Evening Bells", "The bells of the temple rang at six.")),
        ]
    }
}
