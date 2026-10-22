import Foundation

/// The way that the reader turns the pages.
public enum ReadingMode: String, Codable, Sendable, CaseIterable {
    /// One page at a time, from the left to the right, as in a western comic.
    case leftToRight
    /// One page at a time, from the right to the left, as in a manga.
    case rightToLeft
    /// All pages in one column, as in a webtoon.
    case vertical
}

/// The kind of file that a book comes from.
public enum BookFormat: String, Codable, Sendable {
    /// The pages are images: a CBZ, CBR, CB7, CBT, archive, or folder.
    case comic
}

/// One book in the library.
public struct Book: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var author: String?
    public var summary: String?
    public var format: BookFormat
    /// The name of the file that the user imported.
    public var fileName: String
    public var pageCount: Int
    public var added: Date
    public var lastRead: Date?
    /// The page that the user reads now, from 0.
    public var page: Int
    public var finished: Bool
    /// The mode of this book. With nil, the book uses the mode of the library.
    public var mode: ReadingMode?

    public init(
        id: UUID = UUID(), title: String, author: String? = nil, summary: String? = nil,
        format: BookFormat = .comic, fileName: String, pageCount: Int, added: Date = .now,
        lastRead: Date? = nil, page: Int = 0, finished: Bool = false, mode: ReadingMode? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.summary = summary
        self.format = format
        self.fileName = fileName
        self.pageCount = pageCount
        self.added = added
        self.lastRead = lastRead
        self.page = page
        self.finished = finished
        self.mode = mode
    }

    /// The part of the book that the user read, from 0 to 1.
    public var progress: Double {
        if finished { return 1 }
        guard pageCount > 1 else { return 0 }
        return Double(min(max(page, 0), pageCount - 1)) / Double(pageCount - 1)
    }

    /// Keeps the page and the time. The last page marks the book as finished.
    public mutating func read(page newPage: Int, at date: Date = .now) {
        page = min(max(newPage, 0), max(pageCount - 1, 0))
        lastRead = date
        if page == pageCount - 1 { finished = true }
    }
}

/// All data of the library, in one JSON file.
public struct Library: Codable, Sendable, Equatable {
    /// The form of the data. A newer app can read an older form, but not the reverse.
    public static let currentForm = 1

    public var form: Int
    public var books: [Book]
    public var defaultMode: ReadingMode

    public init(books: [Book] = [], defaultMode: ReadingMode = .rightToLeft) {
        self.form = Self.currentForm
        self.books = books
        self.defaultMode = defaultMode
    }

    /// The mode that the reader uses for a book.
    public func mode(of book: Book) -> ReadingMode {
        book.mode ?? defaultMode
    }

    /// The books that the user started and did not finish, the last one first.
    public var continueReading: [Book] {
        books.filter { $0.lastRead != nil && !$0.finished }
            .sorted { ($0.lastRead ?? .distantPast) > ($1.lastRead ?? .distantPast) }
    }

    /// All books, the newest first.
    public var recentlyAdded: [Book] {
        books.sorted { $0.added > $1.added }
    }
}

public enum LibraryError: Error, Equatable {
    /// The file comes from a newer version of the app.
    case newerForm(Int)
}

/// Reads and writes the library file.
public enum LibraryStore {
    public static func load(from url: URL) throws -> Library {
        guard FileManager.default.fileExists(atPath: url.path) else { return Library() }
        let data = try Data(contentsOf: url)
        let form = try decoder.decode(FormOnly.self, from: data).form
        guard form <= Library.currentForm else { throw LibraryError.newerForm(form) }
        return try decoder.decode(Library.self, from: data)
    }

    public static func save(_ library: Library, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(library).write(to: url, options: .atomic)
    }

    private struct FormOnly: Decodable { let form: Int }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
