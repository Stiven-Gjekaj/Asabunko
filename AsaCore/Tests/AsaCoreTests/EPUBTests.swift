import Foundation
import Testing
@testable import AsaCore

private func epub(
    opf: String, extra: [(String, Data)] = [], opfPath: String = "OEBPS/content.opf"
) -> [(String, Data)] {
    [
        ("mimetype", Data("application/epub+zip".utf8)),
        ("META-INF/container.xml", Data("""
        <?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles><rootfile full-path="\(opfPath)" media-type="application/oebps-package+xml"/></rootfiles></container>
        """.utf8)),
        (opfPath, Data(opf.utf8)),
    ] + extra
}

private func chapter(_ text: String) -> Data {
    Data("<?xml version=\"1.0\"?><html xmlns=\"http://www.w3.org/1999/xhtml\"><body><p>\(text)</p></body></html>".utf8)
}

@Suite struct EPUBTests {
    @Test func readsTheSpineTheTitlesOfTheNavAndTheCover() throws {
        let work = try temporaryFolder()
        let file = work.appendingPathComponent("book.epub")
        let opf = """
        <?xml version="1.0"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>The Quiet Library</dc:title><dc:creator>A. Writer</dc:creator><dc:creator>B. Writer</dc:creator>
            <dc:language>en</dc:language><dc:description>&lt;p&gt;A calm &lt;b&gt;story&lt;/b&gt;.&lt;/p&gt;</dc:description>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="c2" href="text/two%20b.xhtml" media-type="application/xhtml+xml"/>
            <item id="c1" href="text/one.xhtml" media-type="application/xhtml+xml"/>
            <item id="img" href="images/cover.png" media-type="image/png" properties="cover-image"/>
          </manifest>
          <spine page-progression-direction="rtl"><itemref idref="c1"/><itemref idref="c2"/></spine>
        </package>
        """
        let nav = Data("""
        <?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
        <nav epub:type="landmarks"><ol><li><a href="text/two%20b.xhtml">Wrong</a></li></ol></nav>
        <nav epub:type="toc"><ol><li><a href="text/one.xhtml#start">One&nbsp;Morning</a></li><li><a href="text/two%20b.xhtml">Two</a></li></ol></nav>
        </body></html>
        """.utf8)
        try writeArchive(.zip, to: file, files: epub(opf: opf, extra: [
            ("OEBPS/nav.xhtml", nav), ("OEBPS/text/one.xhtml", chapter("one")), ("OEBPS/text/two b.xhtml", chapter("two")),
            ("OEBPS/images/cover.png", pngData(width: 300, height: 450)), ("../escape.txt", Data("x".utf8)),
        ]))
        let folder = work.appendingPathComponent("book")

        let result = try BookImporter.importBook(from: file, into: folder)

        #expect(result.format == .novel)
        #expect(result.title == "The Quiet Library")
        #expect(result.author == "A. Writer, B. Writer")
        #expect(result.summary == "A calm story .")
        #expect(result.pageCount == 2)
        let novel = try Novel.load(from: folder)
        #expect(novel.rightToLeft)
        #expect(novel.language == "en")
        #expect(novel.chapters == [
            .init(title: "One Morning", path: "content/OEBPS/text/one.xhtml"),
            .init(title: "Two", path: "content/OEBPS/text/two b.xhtml"),
        ])
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("content/OEBPS/text/two b.xhtml").path))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("cover.jpg").path))
        #expect(!FileManager.default.fileExists(atPath: work.appendingPathComponent("escape.txt").path))
    }

    @Test func readsTheTitlesOfAnNCXInAnEPUB2() throws {
        let work = try temporaryFolder()
        let file = work.appendingPathComponent("old.epub")
        let opf = """
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>Old</dc:title><meta name="cover" content="cv"/></metadata>
        <manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
        <item id="a" href="a.html" media-type="application/xhtml+xml"/><item id="cv" href="c.jpg" media-type="image/jpeg"/></manifest>
        <spine toc="ncx"><itemref idref="a"/></spine></package>
        """
        let ncx = Data("""
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap><navPoint id="p"><navLabel><text>First</text></navLabel>
        <content src="a.html"/></navPoint></navMap></ncx>
        """.utf8)
        try writeArchive(.zip, to: file, files: epub(opf: opf, extra: [("toc.ncx", ncx), ("a.html", chapter("a"))], opfPath: "content.opf"))
        _ = try BookImporter.importBook(from: file, into: work.appendingPathComponent("b"))
        let novel = try Novel.load(from: work.appendingPathComponent("b"))
        #expect(novel.chapters == [.init(title: "First", path: "content/a.html")])
        #expect(!novel.rightToLeft)
    }

    @Test func refusesAnEPUBWithEncryptedChapters() throws {
        let work = try temporaryFolder()
        let file = work.appendingPathComponent("drm.epub")
        let encryption = Data("""
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
        <enc:EncryptedData><enc:CipherData><enc:CipherReference URI="OEBPS/a.xhtml"/></enc:CipherData></enc:EncryptedData></encryption>
        """.utf8)
        try writeArchive(.zip, to: file, files: epub(opf: "<package/>", extra: [("META-INF/encryption.xml", encryption)]))
        let folder = work.appendingPathComponent("b")
        #expect(throws: EPUBImporter.Failure.encrypted) { try BookImporter.importBook(from: file, into: folder) }
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func normalizesThePaths() {
        #expect(EPUBImporter.normalize("OEBPS/text/../images/./a.png") == "OEBPS/images/a.png")
        #expect(EPUBImporter.safePath("a/../../b") == nil)
        #expect(EPUBImporter.safePath("/etc/passwd") == nil)
        #expect(EPUBImporter.safePath("OEBPS/a.xhtml") == "OEBPS/a.xhtml")
    }
}
