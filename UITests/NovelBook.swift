import Foundation

/// An EPUB of three short chapters that the tests of novels make.
enum NovelBook {
    private static func page(_ title: String, _ text: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>\(title)</title>
        <script>document.body.innerHTML = 'SCRIPT RAN';</script></head>
        <body><h2>\(title)</h2><p>\(text)</p><p>\(String(repeating: "A quiet line of the morning. ", count: 60))</p></body></html>
        """.utf8)
    }

    static var epub: [(String, Data)] {
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
