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

    @Test func sortsTheReadListInEachOrder() {
        let a = Book(title: "Bay 10", fileName: "a", pageCount: 10, added: Date(timeIntervalSince1970: 300), lastRead: Date(timeIntervalSince1970: 100), page: 5)
        let b = Book(title: "Bay 9", fileName: "b", pageCount: 10, added: Date(timeIntervalSince1970: 200), lastRead: Date(timeIntervalSince1970: 400), finished: true)
        let c = Book(title: "Arch", fileName: "c", pageCount: 10, added: Date(timeIntervalSince1970: 100))
        let library = Library(books: [a, b, c])
        #expect(library.readList(by: .added).map(\.title) == ["Bay 10", "Bay 9", "Arch"])
        #expect(library.readList(by: .lastRead).map(\.title) == ["Bay 9", "Bay 10", "Arch"])
        #expect(library.readList(by: .title).map(\.title) == ["Arch", "Bay 9", "Bay 10"], "The numbers sort in natural order.")
        #expect(library.readList(by: .unread).map(\.title) == ["Arch", "Bay 10", "Bay 9"])
    }

    @Test func aBookFindsItsSourceWhenItsListComesBack() {
        let old = UUID(), new = UUID()
        let info = SourceInfo(id: "en.sea", name: "Sea", language: "en", version: "1", icon: nil, code: URL(string: "https://x.test/s.aix")!, novels: false)
        var library = Library(books: [
            Book(title: "Lost", fileName: "Sea", pageCount: 1, origin: BookOrigin(list: old, source: "en.sea", series: "s1")),
            Book(title: "Other", fileName: "Hill", pageCount: 1, origin: BookOrigin(list: old, source: "en.hill", series: "h1")),
        ], sources: [SourceLink(id: new, url: URL(string: "https://x.test/index.min.json")!)])
        library.installed = [InstalledSource(list: new, info: info)]
        #expect(library.relinkOrphans() == 1)
        #expect(library.books[0].origin?.list == new)
        #expect(library.books[1].origin?.list == old, "A book with no installed source keeps its old list.")
        #expect(library.relinkOrphans() == 0)
    }

    @Test func keepsACopyOfALibraryThatTheAppCannotRead() throws {
        let url = try temporaryFolder().appendingPathComponent("library.json")
        try Data(#"{"form":1,"books":[{"id":"bad"}]}"#.utf8).write(to: url)
        #expect(throws: (any Error).self) { try LibraryStore.load(from: url) }
        let copy = try LibraryStore.keepBroken(url, at: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(copy.lastPathComponent.hasPrefix("library.broken-2027-01-15"))
        #expect(try Data(contentsOf: copy) == Data(contentsOf: url))
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

    @Test func keepsTheNewChaptersOfTheChecksNewestFirst() throws {
        let book = Book(title: "Tide", fileName: "t", pageCount: 3)
        var library = Library(books: [book])
        let early = Date(timeIntervalSince1970: 1_000), late = Date(timeIntervalSince1970: 2_000)
        library.record([(1, "Two"), (2, "Three")], of: book.id, at: early)
        library.record([(2, "Three"), (3, "Four")], of: book.id, at: late)
        #expect(library.updates.map(\.chapter) == [3, 2, 1], "A chapter that is in the list does not come two times.")
        #expect(library.updates.first?.found == late)
        library.record((10..<(10 + Library.updateLimit)).map { ($0, nil) }, of: book.id)
        #expect(library.updates.count == Library.updateLimit)
        // A book that left the library does not show its updates.
        library.books = []
        #expect(library.shownUpdates.isEmpty)
        // The updates and the switch of the downloads stay in the file.
        var saved = Library(books: [Book(title: "Sea", fileName: "s", pageCount: 1, autoDownload: true)])
        saved.record([(0, "One")], of: saved.books[0].id)
        let read = try JSONDecoder().decode(Library.self, from: try JSONEncoder().encode(saved))
        #expect(read.updates == saved.updates)
        #expect(read.books[0].autoDownload)
        // A file of an older version has no updates and no switch.
        let old = try JSONDecoder().decode(Library.self, from: Data(#"{"form":1,"books":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"Old","format":"comic","fileName":"o","pageCount":1,"added":0,"page":0,"finished":false}],"defaultMode":"rightToLeft"}"#.utf8))
        #expect(old.updates.isEmpty)
        #expect(old.books[0].autoDownload == false)
    }

    @Test func keepsTheCategoriesOfTheReadList() throws {
        let reading = BookCategory(name: "Reading"), hold = BookCategory(name: "On hold")
        var a = Book(title: "A", fileName: "a", pageCount: 1, added: Date(timeIntervalSince1970: 2))
        a.categories = [reading.id]
        let b = Book(title: "B", fileName: "b", pageCount: 1, added: Date(timeIntervalSince1970: 1), categories: [reading.id, hold.id])
        var library = Library(books: [a, b])
        library.categories = [reading, hold]
        #expect(library.readList(in: nil, by: .added).map(\.title) == ["A", "B"])
        #expect(library.readList(in: hold.id, by: .added).map(\.title) == ["B"])
        library.removeCategory(reading.id)
        #expect(library.categories == [hold])
        #expect(library.books.map(\.categories) == [[], [hold.id]], "A removed category leaves each book.")
        let read = try JSONDecoder().decode(Library.self, from: try JSONEncoder().encode(library))
        #expect(read.categories == [hold])
        #expect(read.books[1].categories == [hold.id])
    }

    @Test func keepsOneEntryOfTheHistoryForEachPlaceOnADay() {
        let book = Book(title: "A", fileName: "a", pageCount: 9)
        var library = Library(books: [book])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = Date(timeIntervalSince1970: 86_400 * 100)
        library.noteVisit(of: book.id, place: 1, at: day, calendar: calendar)
        library.noteVisit(of: book.id, place: 2, at: day.addingTimeInterval(60), calendar: calendar)
        library.noteVisit(of: book.id, place: 1, at: day.addingTimeInterval(120), calendar: calendar)
        #expect(library.history.map(\.place) == [1, 2], "The second visit of chapter 1 takes the place of the first one.")
        library.noteVisit(of: book.id, place: 1, at: day.addingTimeInterval(86_400), calendar: calendar)
        #expect(library.history.map(\.place) == [1, 1, 2], "A visit on another day is a new entry.")
        for place in 0..<(Library.historyLimit + 5) { library.noteVisit(of: book.id, place: 1000 + place, at: day, calendar: calendar) }
        #expect(library.history.count == Library.historyLimit)
        library.books = []
        #expect(library.shownHistory.isEmpty)
    }
}
