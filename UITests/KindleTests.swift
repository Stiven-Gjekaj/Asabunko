import XCTest

/// Imports a MOBI book that the test makes, and reads it.
final class KindleTests: XCTestCase {
    private var app: XCUIApplication!
    private var book: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        book = folder.appendingPathComponent("Harbour_Lights.mobi")
        let html = "<html><body><h1>The Harbour</h1><p>The lamps came on one by one.</p><mbp:pagebreak/><h1>The Ferry</h1><p>The ferry left at nine.</p></body></html>"
        try Self.mobi(text: Data(html.utf8), title: "Harbour Lights", author: "Ana Reyes").write(to: book)
        app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = folder.appendingPathComponent("library").path
        app.launch()
    }

    func testImportsAndReadsAMOBIBook() throws {
        XCTAssertTrue(app.staticTexts["Your shelf is empty"].waitForExistence(timeout: 10))
        app.open(book)
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Harbour Lights'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 15), "The title comes from the EXTH header of the book.")
        tile.tap()
        XCTAssertTrue(app.staticTexts["Chapter 1 of 2"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS 'lamps came on'")).firstMatch.waitForExistence(timeout: 10))
        shot("1 MOBI chapter")
        app.buttons["Chapters"].tap()
        XCTAssertTrue(app.buttons["The Ferry"].waitForExistence(timeout: 5), "The page break makes the second chapter.")
        app.buttons["The Ferry"].tap()
        XCTAssertTrue(app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS 'ferry left'")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["Close"].tap()
    }

    /// A MOBI 6 file with no compression: record 0 with the MOBI and EXTH headers, and one text record.
    static func mobi(text: Data, title: String, author: String) -> Data {
        func be32(_ v: UInt32) -> Data { Data([UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]) }
        func be16(_ v: UInt16) -> Data { Data([UInt8(v >> 8), UInt8(v & 0xFF)]) }
        var exth = Data()
        for (type, value) in [(100, author), (503, title)] {
            exth += be32(UInt32(type)) + be32(UInt32(8 + value.utf8.count)) + Data(value.utf8)
        }
        exth = Data("EXTH".utf8) + be32(UInt32(12 + exth.count)) + be32(2) + exth
        var mobi = Data(count: 0xE8)
        func put(_ value: UInt32, at offset: Int) { mobi.replaceSubrange(offset..<(offset + 4), with: be32(value)) }
        mobi.replaceSubrange(0..<4, with: Data("MOBI".utf8))
        put(0xE8, at: 4)
        put(65001, at: 12)
        put(6, at: 20)
        put(0xFFFF_FFFF, at: 0x5C)
        put(0x40, at: 0x70)
        let record0 = be16(1) + be16(0) + be32(UInt32(text.count)) + be16(1) + be16(4096) + be16(0) + be16(0) + mobi + exth
        let records = [record0, text]
        var offset = 78 + records.count * 8 + 2
        var file = Data(count: 60) + Data("BOOKMOBI".utf8) + Data(count: 8) + be16(UInt16(records.count))
        for record in records {
            file += be32(UInt32(offset)) + Data(count: 4)
            offset += record.count
        }
        file += Data(count: 2)
        for record in records { file += record }
        return file
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
