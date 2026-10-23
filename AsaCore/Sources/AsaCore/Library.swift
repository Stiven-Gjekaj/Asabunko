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
    /// The book is text in chapters: an EPUB, TXT, FB2, or HTML file.
    case novel
    /// The book is a PDF, which keeps its pages as they are.
    case pdf
    /// The book is a series of an online source: chapters of pages that come from the network.
    case series
}

/// The online source of a book, so that the app can get its new chapters.
public struct BookOrigin: Codable, Sendable, Equatable, Hashable {
    /// The line of the source list.
    public var list: UUID
    /// The source in that list, such as the ID of an LNReader plugin. Empty for an OPDS catalog or a server.
    public var source: String
    /// The series or the novel in the source.
    public var series: String

    public init(list: UUID, source: String, series: String) {
        self.list = list
        self.source = source
        self.series = series
    }
}

/// A source that the user installed from a list.
public struct InstalledSource: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var list: UUID
    public var info: SourceInfo
    public var id: String { "\(list.uuidString)/\(info.id)" }

    public init(list: UUID, info: SourceInfo) {
        self.list = list
        self.info = info
    }
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
    /// The page that the user reads now, from 0. In a novel, it is the chapter.
    public var page: Int
    /// The part of the chapter of a novel that the user read, from 0 to 1.
    public var position: Double
    public var finished: Bool
    /// The mode of this book. With nil, the book uses the mode of the library.
    public var mode: ReadingMode?
    /// The online source of the book, or nil for a book from a file.
    public var origin: BookOrigin?
    /// True when the book is in the read list. A series that the user only opened is not.
    public var listed: Bool
    /// True when each new chapter that a check finds downloads with no question.
    public var autoDownload: Bool
    /// The categories of the read list that the book is in.
    public var categories: [UUID]
    /// The entries of the book on AniList or MyAnimeList.
    public var tracking: [TrackLink]

    public init(
        id: UUID = UUID(), title: String, author: String? = nil, summary: String? = nil,
        format: BookFormat = .comic, fileName: String, pageCount: Int, added: Date = .now,
        lastRead: Date? = nil, page: Int = 0, position: Double = 0, finished: Bool = false, mode: ReadingMode? = nil,
        origin: BookOrigin? = nil, listed: Bool = true, autoDownload: Bool = false, categories: [UUID] = [],
        tracking: [TrackLink] = []
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
        self.position = position
        self.finished = finished
        self.mode = mode
        self.origin = origin
        self.listed = listed
        self.autoDownload = autoDownload
        self.categories = categories
        self.tracking = tracking
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, author, summary, format, fileName, pageCount, added, lastRead, page, position, finished, mode, origin, listed, autoDownload, categories, tracking
    }

    /// A field that an older version did not write gets its first value.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        author = try c.decodeIfPresent(String.self, forKey: .author)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        format = try c.decode(BookFormat.self, forKey: .format)
        fileName = try c.decode(String.self, forKey: .fileName)
        pageCount = try c.decode(Int.self, forKey: .pageCount)
        added = try c.decode(Date.self, forKey: .added)
        lastRead = try c.decodeIfPresent(Date.self, forKey: .lastRead)
        page = try c.decode(Int.self, forKey: .page)
        position = try c.decodeIfPresent(Double.self, forKey: .position) ?? 0
        finished = try c.decode(Bool.self, forKey: .finished)
        mode = try c.decodeIfPresent(ReadingMode.self, forKey: .mode)
        origin = try c.decodeIfPresent(BookOrigin.self, forKey: .origin)
        // Before the read list, the user added each book on purpose.
        listed = try c.decodeIfPresent(Bool.self, forKey: .listed) ?? true
        autoDownload = try c.decodeIfPresent(Bool.self, forKey: .autoDownload) ?? false
        categories = try c.decodeIfPresent([UUID].self, forKey: .categories) ?? []
        tracking = try c.decodeIfPresent([TrackLink].self, forKey: .tracking) ?? []
    }

    /// The part of the book that the user read, from 0 to 1.
    public var progress: Double {
        if finished { return 1 }
        if format == .novel || format == .series {
            guard pageCount > 0 else { return 0 }
            return min((Double(min(max(page, 0), pageCount - 1)) + min(max(position, 0), 1)) / Double(pageCount), 1)
        }
        guard pageCount > 1 else { return 0 }
        return Double(min(max(page, 0), pageCount - 1)) / Double(pageCount - 1)
    }

    /// Keeps the chapter and the place in it. The end of the last chapter marks the novel as finished.
    public mutating func read(chapter: Int, position newPosition: Double, at date: Date = .now) {
        page = min(max(chapter, 0), max(pageCount - 1, 0))
        position = min(max(newPosition, 0), 1)
        lastRead = date
        if page == pageCount - 1 && position >= 0.98 { finished = true }
    }

    /// Keeps the page and the time. The last page marks the book as finished.
    public mutating func read(page newPage: Int, at date: Date = .now) {
        page = min(max(newPage, 0), max(pageCount - 1, 0))
        lastRead = date
        if page == pageCount - 1 { finished = true }
    }
}

/// The orders of the read list.
public enum ReadListOrder: String, CaseIterable, Sendable {
    case added, lastRead, title, unread

    public var name: String {
        switch self {
        case .added: "Date added"
        case .lastRead: "Last read"
        case .title: "Title"
        case .unread: "Unread first"
        }
    }
}

/// A category of the read list, such as "Reading" or "On hold".
public struct BookCategory: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

/// One time that the user opened a chapter or a page of a book.
public struct HistoryEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var book: UUID
    /// The chapter of a novel or a series, or the page of a comic, from 0.
    public var place: Int
    public var date: Date

    public init(id: UUID = UUID(), book: UUID, place: Int, date: Date) {
        self.id = id; self.book = book; self.place = place; self.date = date
    }
}

/// A bookmark or a highlight in a chapter of a novel.
public struct BookMark: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case bookmark, highlight }

    public var id: UUID
    public var book: UUID
    public var chapter: Int
    /// The place in the chapter, from 0 to 1.
    public var position: Double
    /// The words of a highlight, or the first words at the place of a bookmark.
    public var text: String
    public var kind: Kind
    public var created: Date

    public init(id: UUID = UUID(), book: UUID, chapter: Int, position: Double, text: String, kind: Kind, created: Date = .now) {
        self.id = id; self.book = book; self.chapter = chapter; self.position = min(max(position, 0), 1)
        self.text = text; self.kind = kind; self.created = created
    }
}

/// A new chapter that a check found.
public struct ChapterUpdate: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var book: UUID
    /// The index of the chapter in the book, from 0.
    public var chapter: Int
    public var title: String?
    public var found: Date

    public init(id: UUID = UUID(), book: UUID, chapter: Int, title: String?, found: Date) {
        self.id = id; self.book = book; self.chapter = chapter; self.title = title; self.found = found
    }
}

/// All data of the library, in one JSON file.
public struct Library: Codable, Sendable, Equatable {
    /// The form of the data. A newer app can read an older form, but not the reverse.
    public static let currentForm = 1

    public var form: Int
    public var books: [Book]
    public var defaultMode: ReadingMode
    public var sources: [SourceLink]
    public var installed: [InstalledSource]
    /// The new chapters that the checks found, the newest first.
    public var updates: [ChapterUpdate]
    /// The list of updates keeps at most this number of chapters.
    public static let updateLimit = 300
    /// The categories of the read list, in the order of the user.
    public var categories: [BookCategory]
    /// The chapters and the books that the user opened, the newest first.
    public var history: [HistoryEntry]
    public static let historyLimit = 500
    /// The bookmarks and the highlights of the novels.
    public var marks: [BookMark]

    public init(books: [Book] = [], defaultMode: ReadingMode = .rightToLeft, sources: [SourceLink] = []) {
        self.form = Self.currentForm
        self.books = books
        self.defaultMode = defaultMode
        self.sources = sources
        self.installed = []
        self.updates = []
        self.categories = []
        self.history = []
        self.marks = []
    }

    private enum CodingKeys: String, CodingKey { case form, books, defaultMode, sources, installed, updates, categories, history, marks }

    /// A list that an older version did not write is empty.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        form = try c.decode(Int.self, forKey: .form)
        books = try c.decode([Book].self, forKey: .books)
        defaultMode = try c.decode(ReadingMode.self, forKey: .defaultMode)
        sources = try c.decodeIfPresent([SourceLink].self, forKey: .sources) ?? []
        installed = try c.decodeIfPresent([InstalledSource].self, forKey: .installed) ?? []
        updates = try c.decodeIfPresent([ChapterUpdate].self, forKey: .updates) ?? []
        categories = try c.decodeIfPresent([BookCategory].self, forKey: .categories) ?? []
        history = try c.decodeIfPresent([HistoryEntry].self, forKey: .history) ?? []
        marks = try c.decodeIfPresent([BookMark].self, forKey: .marks) ?? []
    }

    /// Keeps a visit of a book in the history. A visit of the same place of the same book on the same day
    /// takes the place of the older one, so that the turns of the pages of one chapter give one entry.
    public mutating func noteVisit(of book: UUID, place: Int, at date: Date = .now, calendar: Calendar = .current) {
        history.removeAll { $0.book == book && $0.place == place && calendar.isDate($0.date, inSameDayAs: date) }
        history.insert(HistoryEntry(book: book, place: place, date: date), at: 0)
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
    }

    /// The marks of a book in the order of the book: by chapter, then by place.
    public func marks(of book: UUID) -> [BookMark] {
        marks.filter { $0.book == book }.sorted { ($0.chapter, $0.position) < ($1.chapter, $1.position) }
    }

    /// The history of the books that are in the library.
    public var shownHistory: [HistoryEntry] {
        let ids = Set(books.map(\.id))
        return history.filter { ids.contains($0.book) }
    }

    /// The books of a category of the read list. With nil, all books of the read list.
    public func readList(in category: UUID?, by order: ReadListOrder) -> [Book] {
        let list = readList(by: order)
        guard let category else { return list }
        return list.filter { $0.categories.contains(category) }
    }

    /// Removes a category, and takes it off each book.
    public mutating func removeCategory(_ id: UUID) {
        categories.removeAll { $0.id == id }
        for index in books.indices { books[index].categories.removeAll { $0 == id } }
    }

    /// Keeps the new chapters of a book at the top of the updates. A chapter that is in the list already does not come two times.
    public mutating func record(_ chapters: [(index: Int, title: String?)], of book: UUID, at date: Date = .now) {
        let known = Set(updates.filter { $0.book == book }.map(\.chapter))
        // The last chapter comes first, as in the list of the source.
        let new = chapters.filter { !known.contains($0.index) }.sorted { $0.index > $1.index }
            .map { ChapterUpdate(book: book, chapter: $0.index, title: $0.title, found: date) }
        updates = Array((new + updates).prefix(Self.updateLimit))
    }

    /// The updates of the books that are in the library, the newest first.
    public var shownUpdates: [ChapterUpdate] {
        let ids = Set(books.map(\.id))
        return updates.filter { ids.contains($0.book) }
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

    /// The book of a series or a novel of a source, when the library has it.
    public func book(from origin: BookOrigin) -> Book? {
        books.first { $0.origin == origin }
    }

    /// Links each book of a list that left the source list to an installed source with the same ID.
    /// A line that the user removes and adds again gets a new ID, and its books find their source again.
    /// - Returns: the number of books that found their source.
    @discardableResult
    public mutating func relinkOrphans() -> Int {
        let lists = Set(sources.map(\.id))
        var linked = 0
        for index in books.indices {
            guard let origin = books[index].origin, !lists.contains(origin.list),
                  let match = installed.first(where: { $0.info.id == origin.source && lists.contains($0.list) })
            else { continue }
            books[index].origin?.list = match.list
            linked += 1
        }
        return linked
    }

    /// The books of the read list, the newest first.
    public var readList: [Book] {
        recentlyAdded.filter(\.listed)
    }

    /// The books of the read list in an order that the user chooses.
    public func readList(by order: ReadListOrder) -> [Book] {
        let list = readList
        switch order {
        case .added: return list
        case .lastRead: return list.sorted { ($0.lastRead ?? .distantPast) > ($1.lastRead ?? .distantPast) }
        case .title: return list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        // The books that the user did not finish come first, the least read first.
        case .unread: return list.sorted { ($0.finished ? 2 : $0.progress) < ($1.finished ? 2 : $1.progress) }
        }
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

    /// Copies a library file that the app cannot read next to it, as library.broken-<date>.json,
    /// so that no save can write over it. It gives the URL of the copy.
    @discardableResult
    public static func keepBroken(_ url: URL, at date: Date = .now) throws -> URL {
        let stamp = date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "-")
        let copy = url.deletingLastPathComponent().appendingPathComponent("library.broken-\(stamp).json")
        if FileManager.default.fileExists(atPath: copy.path) { try FileManager.default.removeItem(at: copy) }
        try FileManager.default.copyItem(at: url, to: copy)
        return copy
    }

    public static func save(_ library: Library, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(library).write(to: url, options: .atomic)
    }

    private struct FormOnly: Decodable { let form: Int }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // The app writes the file after each page, so the file has no spaces. A large library writes faster.
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
