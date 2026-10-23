import Foundation
import Testing
@testable import AsaCore

@Suite struct BookExportTests {
    @Test func sharesAComicAsACBZThatImportsAgain() throws {
        let work = try temporaryFolder()
        let source = work.appendingPathComponent("in.cbz")
        let pages = (1...3).map { ("\($0).png", pngData(gray: CGFloat($0) / 4)) }
        try writeArchive(.zip, to: source, files: pages)
        let folder = work.appendingPathComponent("book")
        _ = try BookImporter.importBook(from: source, into: folder)

        let file = try #require(try BookExport.file(of: .comic, title: "Harbor: Lights/1", folder: folder, into: work.appendingPathComponent("out")))
        #expect(file.lastPathComponent == "Harbor  Lights 1.cbz", "A character that a file name cannot hold becomes a space.")
        let again = try BookImporter.importBook(from: file, into: work.appendingPathComponent("again"))
        #expect(again.format == .comic)
        #expect(again.pageCount == 3)
        let first = try #require(ComicImporter.pages(in: work.appendingPathComponent("again")).first)
        #expect(try Data(contentsOf: first) == pages[0].1)
    }

    @Test func sharesTheEPUBOfANovelWithItsMimetypeFirst() throws {
        let work = try temporaryFolder()
        let source = work.appendingPathComponent("in.epub")
        let page = Data("<?xml version=\"1.0\"?><html xmlns=\"http://www.w3.org/1999/xhtml\"><body><p>Rain.</p></body></html>".utf8)
        try writeArchive(.zip, to: source, files: [
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data("""
            <?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
            <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
            """.utf8)),
            ("OEBPS/content.opf", Data("""
            <?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0">
            <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Rain</dc:title></metadata>
            <manifest><item id="a" href="a.xhtml" media-type="application/xhtml+xml"/><item id="b" href="b.xhtml" media-type="application/xhtml+xml"/></manifest>
            <spine><itemref idref="a"/><itemref idref="b"/></spine></package>
            """.utf8)),
            ("OEBPS/a.xhtml", page), ("OEBPS/b.xhtml", page),
        ])
        let folder = work.appendingPathComponent("book")
        _ = try BookImporter.importBook(from: source, into: folder)
        #expect(BookExport.canShare(.novel, folder: folder))

        let file = try #require(try BookExport.file(of: .novel, title: "Rain", folder: folder, into: work))
        let bytes = try Data(contentsOf: file)
        // The first entry of the archive is "mimetype", with no compression, so its text is at byte 38.
        #expect(String(decoding: bytes[30..<38], as: UTF8.self) == "mimetype")
        #expect(String(decoding: bytes[38..<58], as: UTF8.self) == "application/epub+zip")
        let again = try BookImporter.importBook(from: file, into: work.appendingPathComponent("again"))
        #expect(again.format == .novel)
        #expect(again.pageCount == 2)
    }

    @Test func sharesNoFileOfANovelFromText() throws {
        let work = try temporaryFolder()
        let source = work.appendingPathComponent("in.txt")
        try Data("Chapter 1\n\nA line.\n".utf8).write(to: source)
        let folder = work.appendingPathComponent("book")
        _ = try BookImporter.importBook(from: source, into: folder)
        #expect(!BookExport.canShare(.novel, folder: folder))
        #expect(try BookExport.file(of: .novel, title: "T", folder: folder, into: work) == nil)
    }
}
