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

    @Test func readsALibraryOfAnOlderVersionWithNoServers() throws {
        let url = try temporaryFolder().appendingPathComponent("library.json")
        try Data(#"{"form": 1, "books": [], "defaultMode": "vertical"}"#.utf8).write(to: url)
        let library = try LibraryStore.load(from: url)
        #expect(library.servers.isEmpty)
        #expect(library.defaultMode == .vertical)
    }

    @Test func keepsTheServersButNotTheirPasswords() throws {
        let url = try temporaryFolder().appendingPathComponent("library.json")
        let server = CatalogServer(name: "Komga", url: URL(string: "https://komga.local/opds/v1.2/catalog")!, username: "asa")
        try LibraryStore.save(Library(servers: [server]), to: url)
        #expect(try LibraryStore.load(from: url).servers == [server])
        #expect(!(try String(contentsOf: url, encoding: .utf8)).contains("password"))
    }
}
