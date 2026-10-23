import Foundation
import Testing
@testable import AsaCore

@Suite struct BackupTests {
    private let origin = BookOrigin(list: UUID(), source: "quiet", series: "novel/dawn")

    /// A date in whole seconds, because a backup writes the dates in ISO 8601 with no fractions.
    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    private func library() -> Library {
        var library = Library(books: [
            Book(title: "From a file", fileName: "a.cbz", pageCount: 10, added: day, page: 4),
            Book(title: "Lost file", fileName: "b.epub", pageCount: 3, added: day),
            Book(title: "Dawn Tea", format: .novel, fileName: "Quiet", pageCount: 2, added: day, page: 1, position: 0.5, origin: origin),
        ], defaultMode: .vertical, sources: [SourceLink(url: URL(string: "https://x.test/plugins.min.json")!, username: "asa", kind: .lnreader)])
        library.installed = [InstalledSource(list: origin.list, info: SourceInfo(id: "quiet", name: "Quiet", language: "English", version: "1", icon: nil, code: URL(string: "https://x.test/q.js")!, novels: true))]
        return library
    }

    @Test func writesAndReadsTheSameBackup() throws {
        let library = library()
        let novel = Novel(title: "Dawn Tea", chapters: [.init(title: "One", path: "chapters/00001.html", remote: "c/1")])
        let backup = Backup(library: library, chapters: [library.books[2].id: novel], app: "Asabunko", created: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(try Backup.decode(try backup.encoded()) == backup)
    }

    @Test func bringsBackTheOnlineBooksAndTheBooksWithTheirFiles() {
        let library = library()
        let novel = Novel(title: "Dawn Tea", chapters: [])
        let backup = Backup(library: library, chapters: [library.books[2].id: novel], app: "Asabunko")
        let plan = backup.plan { $0 == library.books[0].id }
        #expect(plan.library.books.map(\.title) == ["From a file", "Dawn Tea"])
        #expect(plan.library.books[1].position == 0.5)
        #expect(plan.chapters.keys.sorted { $0.uuidString < $1.uuidString } == [library.books[2].id])
        #expect(plan.skipped == ["Lost file"])
        #expect(plan.library.sources == library.sources)
        #expect(plan.library.installed == library.installed)
    }

    @Test func refusesAFileThatIsNotABackupAndABackupOfANewerApp() {
        #expect(throws: Backup.Failure.notABackup) { try Backup.decode(Data(#"{"form": 1, "books": []}"#.utf8)) }
        #expect(throws: Backup.Failure.newer(9)) { try Backup.decode(Data(#"{"form": 9, "app": "Asabunko"}"#.utf8)) }
    }
}
