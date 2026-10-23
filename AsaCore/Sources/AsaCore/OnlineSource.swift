import Foundation

/// A series or a novel of an online source, in a list.
public struct OnlineSeries: Codable, Sendable, Hashable, Identifiable {
    /// The ID of the series in its source, such as a path or a key.
    public var id: String
    public var title: String
    public var cover: URL?

    public init(id: String, title: String, cover: URL? = nil) {
        self.id = id
        self.title = title
        self.cover = cover
    }
}

/// One chapter of a series or of a novel.
public struct OnlineChapter: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var number: Double?
    public var date: String?
    public var group: String?

    public init(id: String, title: String, number: Double? = nil, date: String? = nil, group: String? = nil) {
        self.id = id
        self.title = title
        self.number = number
        self.date = date
        self.group = group
    }
}

/// The page of a series or a novel, with its chapters from the first to the last.
public struct OnlineDetails: Codable, Sendable, Equatable {
    public var series: OnlineSeries
    public var author: String?
    public var summary: String?
    public var status: String?
    public var genres: [String]
    public var chapters: [OnlineChapter]

    public init(series: OnlineSeries, author: String? = nil, summary: String? = nil, status: String? = nil, genres: [String] = [], chapters: [OnlineChapter] = []) {
        self.series = series
        self.author = author
        self.summary = summary
        self.status = status
        self.genres = genres
        self.chapters = chapters
    }
}

/// One page of the results of a list or a search.
public struct OnlinePage: Sendable, Equatable {
    public var items: [OnlineSeries]
    public var hasMore: Bool

    public init(items: [OnlineSeries], hasMore: Bool) {
        self.items = items
        self.hasMore = hasMore
    }
}

/// What a chapter holds: the pages of a comic, or the HTML of a chapter of a novel.
public enum ChapterContent: Sendable, Equatable {
    case pages([URLRequest])
    case html(String)
}

/// The facts of one source of an ecosystem, from its list.
public struct SourceInfo: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var language: String
    public var version: String
    public var icon: URL?
    /// The URL of the code of the source.
    public var code: URL
    /// True for novels, false for comics.
    public var novels: Bool
    /// True when the source can show adult content.
    public var adult: Bool
    /// True when the source has a list of the latest updates.
    public var hasLatest: Bool

    public init(id: String, name: String, language: String, version: String, icon: URL?, code: URL, novels: Bool, adult: Bool = false, hasLatest: Bool = true) {
        self.id = id
        self.name = name
        self.language = language
        self.version = version
        self.icon = icon
        self.code = code
        self.novels = novels
        self.adult = adult
        self.hasLatest = hasLatest
    }

    private enum CodingKeys: String, CodingKey { case id, name, language, version, icon, code, novels, adult, hasLatest }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        language = try c.decode(String.self, forKey: .language)
        version = try c.decode(String.self, forKey: .version)
        icon = try c.decodeIfPresent(URL.self, forKey: .icon)
        code = try c.decode(URL.self, forKey: .code)
        novels = try c.decode(Bool.self, forKey: .novels)
        adult = try c.decodeIfPresent(Bool.self, forKey: .adult) ?? false
        hasLatest = try c.decodeIfPresent(Bool.self, forKey: .hasLatest) ?? true
    }
}

/// A source that the app has loaded: an LNReader plugin, an Aidoku source, a Paperback extension, or a Suwayomi source.
public protocol OnlineSource: AnyObject, Sendable {
    var info: SourceInfo { get }
    var canShowLatest: Bool { get }
    func popular(page: Int) async throws -> OnlinePage
    func latest(page: Int) async throws -> OnlinePage
    func search(_ query: String, page: Int) async throws -> OnlinePage
    func details(of series: OnlineSeries) async throws -> OnlineDetails
    func content(of chapter: OnlineChapter, in series: OnlineSeries) async throws -> ChapterContent
    /// The request of an image of the source, such as a cover, with the headers that the source needs.
    func imageRequest(_ url: URL) -> URLRequest
}

extension URL {
    /// A URL from text that can hold characters that URL refuses, such as "[" and "]".
    public init?(lenient text: String) {
        if let url = URL(string: text) {
            self = url
        } else if let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed.union(.urlQueryAllowed)),
                  let url = URL(string: encoded) {
            self = url
        } else {
            return nil
        }
    }
}
