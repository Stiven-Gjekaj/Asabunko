import Foundation
import Testing
@testable import AsaCore

@Suite struct LibraryTests {
    @Test func countsTheProgressFromTheFirstToTheLastPage() {
        var book = Book(title: "A", fileName: "a.cbz", pageCount: 5)
        #expect(book.progress == 0)
        book.read(page: 2)
        #expect(book.progress == 0.5)
        #expect(!book.finished)
        book.read(page: 99)
        #expect(book.page == 4)
        #expect(book.finished)
        #expect(book.progress == 1)
    }

    @Test func givesTheStartedBooksTheLastOneFirst() {
        let old = Book(title: "Old", fileName: "o", pageCount: 10, lastRead: Date(timeIntervalSince1970: 100), page: 1)
        let new = Book(title: "New", fileName: "n", pageCount: 10, lastRead: Date(timeIntervalSince1970: 200), page: 1)
        let done = Book(title: "Done", fileName: "d", pageCount: 10, lastRead: Date(timeIntervalSince1970: 300), finished: true)
        let unread = Book(title: "Unread", fileName: "u", pageCount: 10)
        let library = Library(books: [old, done, unread, new])
        #expect(library.continueReading.map(\.title) == ["New", "Old"])
    }

    @Test func theReadListHoldsOnlyListedBooksTheNewestFirst() {
        let old = Book(title: "Old", fileName: "o", pageCount: 1, added: Date(timeIntervalSince1970: 100))
        let new = Book(title: "New", fileName: "n", pageCount: 1, added: Date(timeIntervalSince1970: 200))
        let opened = Book(title: "Opened", fileName: "p", pageCount: 1, added: Date(timeIntervalSince1970: 300), listed: false)
        #expect(Library(books: [old, opened, new]).readList.map(\.title) == ["New", "Old"])
    }

    @Test func aBookOfAnOlderVersionIsInTheReadList() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"A","format":"comic","fileName":"a","pageCount":1,"added":"2026-01-01T00:00:00Z","page":0,"finished":false}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(Book.self, from: Data(json.utf8)).listed)
    }

    @Test func usesTheModeOfTheLibraryWhenABookHasNone() {
        let book = Book(title: "A", fileName: "a", pageCount: 1)
        var library = Library(books: [book], defaultMode: .vertical)
        #expect(library.mode(of: book) == .vertical)
        library.books[0].mode = .leftToRight
        #expect(library.mode(of: library.books[0]) == .leftToRight)
    }

    @Test func writesAndReadsTheSameLibrary() throws {
        let url = try temporaryFolder().appendingPathComponent("data/library.json")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let library = Library(books: [Book(title: "A", fileName: "a.cbz", pageCount: 3, added: date, lastRead: date, page: 1)])
        try LibraryStore.save(library, to: url)
        #expect(try LibraryStore.load(from: url) == library)
    }

    @Test func givesAnEmptyLibraryWhenThereIsNoFile() throws {
        let url = try temporaryFolder().appendingPathComponent("library.json")
        #expect(try LibraryStore.load(from: url) == Library())
    }

    @Test func refusesAFileOfANewerForm() throws {
        let url = try temporaryFolder().appendingPathComponent("library.json")
        try Data(#"{"form": 99, "books": [], "defaultMode": "vertical"}"#.utf8).write(to: url)
        #expect(throws: LibraryError.newerForm(99)) { try LibraryStore.load(from: url) }
    }

    @Test func readsALibraryOfAnOlderVersionWithNoSources() throws {
        let url = try temporaryFolder().appendingPathComponent("library.json")
        try Data(#"{"form": 1, "books": [], "defaultMode": "vertical"}"#.utf8).write(to: url)
        let library = try LibraryStore.load(from: url)
        #expect(library.sources.isEmpty)
        #expect(library.defaultMode == .vertical)
    }
}
