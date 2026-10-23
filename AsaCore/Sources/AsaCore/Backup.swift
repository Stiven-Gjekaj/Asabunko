import Foundation

/// A backup of the library in one JSON file: the books and their places, the source list with no
/// passwords, the installed sources, and the chapters of each online book. The files of the books are not in it.
public struct Backup: Codable, Sendable, Equatable {
    /// The form of the backup. A newer app reads an older backup, but not the reverse.
    public static let currentForm = 1

    public var form: Int
    public var app: String
    public var created: Date
    public var library: Library
    /// The chapters of each online book, by the ID of the book.
    public var chapters: [UUID: Novel]

    public init(library: Library, chapters: [UUID: Novel], app: String, created: Date = .now) {
        self.form = Self.currentForm
        self.app = app
        self.created = created
        self.library = library
        self.chapters = chapters
    }

    public enum Failure: Error, Equatable {
        /// The file is not a backup of Asabunko.
        case notABackup
        /// A newer version of the app made the backup.
        case newer(Int)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> Backup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        struct Head: Decodable { let form: Int; let app: String }
        guard let head = try? decoder.decode(Head.self, from: data), head.app == "Asabunko" else { throw Failure.notABackup }
        guard head.form <= currentForm else { throw Failure.newer(head.form) }
        do { return try decoder.decode(Backup.self, from: data) } catch { throw Failure.notABackup }
    }

    /// What a restore does on this device.
    public struct Plan: Equatable, Sendable {
        /// The library after the restore.
        public var library: Library
        /// The chapters to write for each online book that comes back.
        public var chapters: [UUID: Novel]
        /// The books from files whose files are not on this device.
        public var skipped: [String]
    }

    /// The backup takes the place of the library. A book from a file stays only when `hasFiles` says
    /// that its folder is on the device. An online book always comes back, with its chapters.
    public func plan(hasFiles: (UUID) -> Bool) -> Plan {
        var library = self.library
        var skipped: [String] = []
        library.books = library.books.filter { book in
            if book.origin != nil && chapters[book.id] != nil { return true }
            if hasFiles(book.id) { return true }
            skipped.append(book.title)
            return false
        }
        let kept = Set(library.books.map(\.id))
        return Plan(library: library, chapters: chapters.filter { kept.contains($0.key) }, skipped: skipped)
    }
}
