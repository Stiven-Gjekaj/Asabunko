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

@Suite struct OnlineNovelTests {
    @Test func addsOnlyTheNewChaptersAndKeepsTheOldOnes() {
        var novel = Novel(title: "Dawn", chapters: [])
        #expect(novel.merge([OnlineChapter(id: "c/1", title: "One"), OnlineChapter(id: "c/2", title: "Two")]) == 2)
        #expect(novel.chapters.map(\.path) == ["chapters/00001.html", "chapters/00002.html"])
        // The source removed the first chapter and added a third.
        #expect(novel.merge([OnlineChapter(id: "c/2", title: "Two"), OnlineChapter(id: "c/3", title: "Three")]) == 1)
        #expect(novel.chapters.map(\.remote) == ["c/1", "c/2", "c/3"])
        #expect(novel.chapters[2] == Novel.Chapter(title: "Three", path: "chapters/00003.html", remote: "c/3"))
    }

    @Test func findsTheBookOfASeries() {
        let origin = BookOrigin(list: UUID(), source: "quiet", series: "novel/dawn")
        let library = Library(books: [Book(title: "Dawn", format: .novel, fileName: "", pageCount: 2, origin: origin)])
        #expect(library.book(from: origin)?.title == "Dawn")
        #expect(library.book(from: BookOrigin(list: origin.list, source: "quiet", series: "other")) == nil)
    }
}
