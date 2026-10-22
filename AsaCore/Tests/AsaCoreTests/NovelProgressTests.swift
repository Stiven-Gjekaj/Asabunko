import Foundation
import Testing
@testable import AsaCore

@Suite struct NovelProgressTests {
    @Test func countsTheChaptersAndThePlaceInTheChapter() {
        var book = Book(title: "N", format: .novel, fileName: "n.epub", pageCount: 4)
        book.read(chapter: 1, position: 0.5)
        #expect(book.progress == 0.375)
        #expect(!book.finished)
        book.read(chapter: 3, position: 0.99)
        #expect(book.finished)
    }

    @Test func readsABookOfVersion010WithNoPosition() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"A","format":"comic","fileName":"a","pageCount":2,"added":"2026-10-23T00:00:00Z","page":1,"finished":false}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let book = try decoder.decode(Book.self, from: Data(json.utf8))
        #expect(book.position == 0)
        #expect(book.page == 1)
    }
}
