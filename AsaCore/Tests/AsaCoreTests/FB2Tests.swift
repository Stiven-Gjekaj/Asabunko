import Foundation
import Testing
@testable import AsaCore

@Suite struct FB2Tests {
    @Test func readsTheSectionsTheAuthorAndTheImages() throws {
        let work = try temporaryFolder()
        let file = work.appendingPathComponent("book.fb2")
        let image = pngData(width: 200, height: 300).base64EncodedString()
        try Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
        <description><title-info><author><first-name>Anna</first-name><last-name>Petrova</last-name></author>
        <book-title>Белые ночи</book-title><lang>ru</lang><coverpage><image l:href="#cover"/></coverpage></title-info></description>
        <body><section><title><p>Part One</p></title>
          <section><title><p>Night 1</p></title><p>First &amp; quiet.</p><image l:href="#cover"/></section>
          <section><title><p>Night 2</p></title><p>Second.</p></section>
        </section></body>
        <body name="notes"><section><p>A note.</p></section></body>
        <binary id="cover" content-type="image/png">\(image)</binary>
        </FictionBook>
        """.utf8).write(to: file)
        let folder = work.appendingPathComponent("b")
        let result = try BookImporter.importBook(from: file, into: folder)
        #expect(result.title == "Белые ночи")
        #expect(result.author == "Anna Petrova")
        let novel = try Novel.load(from: folder)
        #expect(novel.chapters.map(\.title) == ["Part One: Night 1", "Night 2"])
        let first = try String(contentsOf: folder.appendingPathComponent(novel.chapters[0].path), encoding: .utf8)
        #expect(first.contains("<p>First &amp; quiet.</p>"))
        #expect(first.contains("<img src=\"images/0.png\""))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("cover.jpg").path))
    }
}
