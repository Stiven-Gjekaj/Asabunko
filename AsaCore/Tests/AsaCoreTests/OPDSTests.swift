import Foundation
import Testing
@testable import AsaCore

@Suite struct OPDSTests {
    let base = URL(string: "https://komga.local:25600/opds/v1.2/catalog")!

    @Test func readsTheNavigationAndTheSearchOfAnAtomFeed() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Komga</title>
          <link rel="search" type="application/opensearchdescription+xml" href="/opds/v1.2/search"/>
          <link rel="next" href="catalog?page=1"/>
          <entry><title>Series</title><id>series</id><content>All series</content>
            <link rel="subsection" type="application/atom+xml;profile=opds-catalog;kind=navigation" href="/opds/v1.2/series"/></entry>
        </feed>
        """
        let feed = try OPDS.parse(Data(xml.utf8), base: base)
        #expect(feed.title == "Komga")
        #expect(feed.navigation == [OPDSLink(title: "Series", url: URL(string: "https://komga.local:25600/opds/v1.2/series")!, summary: "All series")])
        #expect(feed.next == URL(string: "https://komga.local:25600/opds/v1.2/catalog?page=1"))
        #expect(feed.search == .description(URL(string: "https://komga.local:25600/opds/v1.2/search")!))
    }

    @Test func readsAPublicationWithItsFilesItsCoverAndItsStream() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom" xmlns:pse="http://vaemendis.net/opds-pse/ns">
          <title>Berserk</title>
          <entry><title>Volume 1</title><id>urn:uuid:1</id><author><name>Kentaro Miura</name></author>
            <summary>&lt;p&gt;Guts.&lt;/p&gt;</summary>
            <link rel="http://opds-spec.org/image/thumbnail" type="image/jpeg" href="/api/v1/books/1/thumbnail"/>
            <link rel="http://opds-spec.org/acquisition" type="application/zip" href="/api/v1/books/1/file"/>
            <link rel="http://opds-spec.org/acquisition/open-access" type="application/epub+zip" href="/b/1.epub"/>
            <link rel="http://vaemendis.net/opds-pse/stream" type="image/jpeg" pse:count="226"
                  href="/api/v1/books/1/pages/{pageNumber}?zero_based=true&amp;width={maxWidth}"/></entry>
        </feed>
        """
        let book = try #require(try OPDS.parse(Data(xml.utf8), base: base).publications.first)
        #expect(book.title == "Volume 1")
        #expect(book.author == "Kentaro Miura")
        #expect(book.summary == "Guts.")
        #expect(book.image == URL(string: "https://komga.local:25600/api/v1/books/1/thumbnail"))
        #expect(book.download?.fileExtension == "cbz")
        #expect(book.stream?.count == 226)
        #expect(book.stream?.url(page: 3, maxWidth: 800) == URL(string: "https://komga.local:25600/api/v1/books/1/pages/3?zero_based=true&width=800"))
    }

    @Test func opensAStreamAtTheLastPageThatTheServerKeeps() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom" xmlns:pse="http://vaemendis.net/opds-pse/ns"><title>x</title>
          <entry><title>A</title><id>a</id>
            <link rel="http://vaemendis.net/opds-pse/stream" type="image/jpeg" pse:count="20" pse:lastRead="7"
                  href="/komga/opds/v1.2/books/0B1/pages/{pageNumber}?zero_based=true&amp;width={maxWidth}"/></entry>
          <entry><title>B</title><id>b</id>
            <link rel="http://vaemendis.net/opds-pse/stream" type="image/jpeg" pse:count="3" pse:lastRead="9"
                  href="/api/opds/key/series/1/volume/2/chapter/3/image?pageNumber={pageNumber}"/></entry>
        </feed>
        """
        let list = try OPDS.parse(Data(xml.utf8), base: base).publications
        let komga = try #require(list.first?.stream), kavita = try #require(list.last?.stream)
        #expect(komga.startPage == 7)
        #expect(kavita.startPage == 2, "A last page after the end opens the last page.")
        let request = try #require(komga.komgaProgress(page: 7))
        #expect(request.httpMethod == "PATCH")
        #expect(request.url == URL(string: "https://komga.local:25600/komga/api/v1/books/0B1/read-progress"), "The base path of the server stays.")
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self) == #"{"page":8,"completed":false}"#)
        #expect(String(decoding: komga.komgaProgress(page: 19)?.httpBody ?? Data(), as: UTF8.self) == #"{"page":20,"completed":true}"#)
        #expect(kavita.komgaProgress(page: 1) == nil, "Kavita keeps the progress by itself.")
    }

    @Test func skipsAFileThatTheAppCannotImport() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>x</title><entry><title>A</title><id>a</id>
        <link rel="http://opds-spec.org/acquisition" type="application/x-ms-reader" href="a.lit"/>
        <link rel="http://opds-spec.org/acquisition" type="application/pdf" href="a.pdf"/></entry></feed>
        """
        let book = try #require(try OPDS.parse(Data(xml.utf8), base: base).publications.first)
        #expect(book.download?.fileExtension == "pdf")
        #expect(book.download?.url == URL(string: "https://komga.local:25600/opds/v1.2/a.pdf"))
    }

    @Test func knowsTheKindleTypesOfProjectGutenberg() {
        let link = URL(string: "https://www.gutenberg.org/ebooks/11.kf8.images")!
        #expect(OPDS.fileExtension(for: "application/x-mobipocket-ebook", url: link) == "mobi")
        #expect(OPDS.fileExtension(for: "application/vnd.amazon.mobi8-ebook", url: link) == "azw3")
        #expect(OPDS.fileExtension(for: "application/octet-stream", url: link) == nil)
    }

    @Test func readsAnOPDS2FeedWithGroups() throws {
        let json = """
        {"metadata": {"title": "Library"},
         "links": [{"rel": "search", "href": "/opds/v2/search{?query}", "templated": true}, {"rel": "next", "href": "?page=2"}],
         "navigation": [{"href": "/opds/v2/libraries", "title": "Libraries", "type": "application/opds+json"}],
         "groups": [{"metadata": {"title": "Keep reading"},
           "publications": [{"metadata": {"title": "Saga 1", "author": [{"name": "B. K. Vaughan"}], "identifier": "id-1"},
             "links": [{"rel": "http://opds-spec.org/acquisition", "href": "/b/1/file", "type": "application/vnd.comicbook+zip"}],
             "images": [{"href": "/b/1/thumb", "type": "image/jpeg"}]}]}]}
        """
        let feed = try OPDS.parse(Data(json.utf8), base: URL(string: "https://komga.local/opds/v2/catalog")!)
        #expect(feed.title == "Library")
        #expect(feed.navigation.map(\.title) == ["Libraries"])
        #expect(feed.groups.first?.title == "Keep reading")
        let book = try #require(feed.groups.first?.publications.first)
        #expect(book.author == "B. K. Vaughan")
        #expect(book.download?.fileExtension == "cbz")
        #expect(book.image == URL(string: "https://komga.local/b/1/thumb"))
        #expect(feed.search == .template("https://komga.local/opds/v2/search{?query}"))
        #expect(feed.next == URL(string: "https://komga.local/opds/v2/catalog?page=2"))
    }

    @Test func fillsTheTemplatesOfBothVersions() {
        #expect(OPDS.searchURL(template: "https://x.org/search?q={searchTerms}&start={startPage?}", query: "one piece & co")
            == URL(string: "https://x.org/search?q=one%20piece%20%26%20co&start="))
        #expect(OPDS.searchURL(template: "https://x.org/opds/v2/search{?query}", query: "saga")
            == URL(string: "https://x.org/opds/v2/search?query=saga"))
    }

    @Test func readsTheTemplateOfAnOpenSearchDescription() {
        let xml = """
        <OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
        <Url type="text/html" template="https://x.org/html?q={searchTerms}"/>
        <Url type="application/atom+xml;profile=opds-catalog" template="https://x.org/opds/search/{searchTerms}"/>
        </OpenSearchDescription>
        """
        #expect(OPDS.openSearchTemplate(Data(xml.utf8)) == "https://x.org/opds/search/{searchTerms}")
    }

    @Test func refusesAPageThatIsNotAFeed() {
        #expect(throws: OPDSError.notAFeed) { try OPDS.parse(Data("<html><body>Login</body></html>".utf8), base: base) }
    }
}
