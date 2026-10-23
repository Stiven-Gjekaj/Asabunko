import Foundation

/// A Suwayomi server, which runs the extensions of Mihon on a computer and gives them with GraphQL.
/// Each source of the server is one online source of the app.
public struct SuwayomiServer: Sendable {
    public let base: URL
    private let fetcher: Fetcher

    /// `fetcher` adds the user name and the password of the server, when it has them.
    public init(base: URL, fetcher: @escaping Fetcher) {
        var text = base.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        for suffix in ["/api/graphql", "/api/v1"] where text.hasSuffix(suffix) { text.removeLast(suffix.count) }
        self.base = URL(string: text) ?? base
        self.fetcher = fetcher
    }

    public enum Failure: Error, LocalizedError, Equatable {
        case graphQL(String)
        public var errorDescription: String? {
            if case let .graphQL(message) = self { return "The Suwayomi server answered: \(message)" }
            return nil
        }
    }

    private struct Reply<T: Decodable>: Decodable {
        struct Problem: Decodable { let message: String }
        let data: T?
        let errors: [Problem]?
    }

    func query<T: Decodable>(_ type: T.Type, _ text: String, _ variables: [String: Any] = [:]) async throws -> T {
        var request = URLRequest(url: base.appendingPathComponent("api/graphql"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": text, "variables": variables])
        let (data, response) = try await fetcher(request)
        guard (200..<300).contains(response.statusCode) else {
            throw Failure.graphQL(response.statusCode == 401 ? "The user name or the password is not correct." : "HTTP \(response.statusCode)")
        }
        let reply = try JSONDecoder().decode(Reply<T>.self, from: data)
        if let problem = reply.errors?.first { throw Failure.graphQL(problem.message) }
        guard let value = reply.data else { throw Failure.graphQL("No data") }
        return value
    }

    /// A path of the server, such as "/api/v1/manga/1/thumbnail", as a full URL.
    func absolute(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return URL(lenient: path) }
        return URL(lenient: base.absoluteString + (path.hasPrefix("/") ? "" : "/") + path)
    }

    private struct Sources: Decodable {
        struct List: Decodable { let nodes: [Node] }
        struct Node: Decodable {
            let id: String
            let name: String
            let displayName: String?
            let lang: String
            let iconUrl: String?
            let isNsfw: Bool?
            let supportsLatest: Bool?
        }
        let sources: List
    }

    /// The sources of the extensions that the server has. The local source of the server, "0", is not here.
    public func sources() async throws -> [SourceInfo] {
        let reply = try await query(Sources.self, "query { sources { nodes { id name displayName lang iconUrl isNsfw supportsLatest } } }")
        return reply.sources.nodes.filter { $0.id != "0" }.map { node in
            SourceInfo(
                id: node.id, name: node.displayName ?? node.name, language: node.lang, version: "",
                icon: absolute(node.iconUrl), code: base, novels: false, adult: node.isNsfw ?? false, hasLatest: node.supportsLatest ?? true
            )
        }
    }
}

/// One source of a Suwayomi server.
public final class SuwayomiSource: OnlineSource, @unchecked Sendable {
    public let info: SourceInfo
    private let server: SuwayomiServer
    private let authorize: @Sendable (URLRequest) -> URLRequest

    public init(info: SourceInfo, server: SuwayomiServer, authorize: @escaping @Sendable (URLRequest) -> URLRequest) {
        self.info = info
        self.server = server
        self.authorize = authorize
    }

    public var canShowLatest: Bool { info.hasLatest }

    private struct Fetched: Decodable {
        struct Payload: Decodable { let hasNextPage: Bool; let mangas: [Manga] }
        let fetchSourceManga: Payload
    }

    struct Manga: Decodable {
        let id: Int
        let title: String
        let thumbnailUrl: String?
    }

    private func list(_ type: String, page: Int, query text: String? = nil) async throws -> OnlinePage {
        var variables: [String: Any] = ["source": info.id, "type": type, "page": page]
        if let text { variables["query"] = text }
        let reply = try await server.query(Fetched.self, """
        mutation ($source: LongString!, $type: FetchSourceMangaType!, $page: Int!, $query: String) {
          fetchSourceManga(input: { source: $source, type: $type, page: $page, query: $query }) { hasNextPage mangas { id title thumbnailUrl } }
        }
        """, variables)
        let items = reply.fetchSourceManga.mangas.map { OnlineSeries(id: String($0.id), title: $0.title, cover: server.absolute($0.thumbnailUrl)) }
        return OnlinePage(items: items, hasMore: reply.fetchSourceManga.hasNextPage)
    }

    public func popular(page: Int) async throws -> OnlinePage { try await list("POPULAR", page: page) }
    public func latest(page: Int) async throws -> OnlinePage { try await list("LATEST", page: page) }
    public func search(_ query: String, page: Int) async throws -> OnlinePage { try await list("SEARCH", page: page, query: query) }

    private struct Details: Decodable {
        struct MangaPayload: Decodable { let manga: Full }
        struct ChaptersPayload: Decodable { let chapters: [Chapter] }
        struct Full: Decodable {
            let id: Int
            let title: String
            let thumbnailUrl: String?
            let author: String?
            let artist: String?
            let description: String?
            let genre: [String]?
            let status: String?
        }
        struct Chapter: Decodable {
            let id: Int
            let name: String
            let chapterNumber: Double?
            let uploadDate: String?
            let scanlator: String?
            let sourceOrder: Int
        }
        let fetchManga: MangaPayload
        let fetchChapters: ChaptersPayload
    }

    public func details(of series: OnlineSeries) async throws -> OnlineDetails {
        guard let id = Int(series.id) else { throw SuwayomiServer.Failure.graphQL("The ID \(series.id) is not a number.") }
        let reply = try await server.query(Details.self, """
        mutation ($id: Int!) {
          fetchManga(input: { id: $id }) { manga { id title thumbnailUrl author artist description genre status } }
          fetchChapters(input: { mangaId: $id }) { chapters { id name chapterNumber uploadDate scanlator sourceOrder } }
        }
        """, ["id": id])
        let manga = reply.fetchManga.manga
        // A source gives the newest chapter first, with the lowest source order.
        let chapters = reply.fetchChapters.chapters.sorted { $0.sourceOrder > $1.sourceOrder }.map { chapter in
            OnlineChapter(
                id: String(chapter.id), title: chapter.name, number: (chapter.chapterNumber ?? -1) >= 0 ? chapter.chapterNumber : nil,
                date: chapter.uploadDate.flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000).formatted(.iso8601.year().month().day()) },
                group: chapter.scanlator
            )
        }
        let status = manga.status.map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
        return OnlineDetails(
            series: OnlineSeries(id: series.id, title: manga.title, cover: server.absolute(manga.thumbnailUrl) ?? series.cover),
            author: [manga.author, manga.artist].compactMap { $0?.nonEmpty }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: ", ").nonEmpty,
            summary: manga.description?.nonEmpty, status: status == "Unknown" ? nil : status, genres: manga.genre ?? [], chapters: chapters
        )
    }

    private struct Pages: Decodable {
        struct Payload: Decodable { let pages: [String] }
        let fetchChapterPages: Payload
    }

    public func content(of chapter: OnlineChapter, in series: OnlineSeries) async throws -> ChapterContent {
        guard let id = Int(chapter.id) else { throw SuwayomiServer.Failure.graphQL("The ID \(chapter.id) is not a number.") }
        let reply = try await server.query(Pages.self, "mutation ($id: Int!) { fetchChapterPages(input: { chapterId: $id }) { pages } }", ["id": id])
        return .pages(reply.fetchChapterPages.pages.compactMap { server.absolute($0) }.map { imageRequest($0) })
    }

    /// An image of the server needs the user name and the password too.
    public func imageRequest(_ url: URL) -> URLRequest {
        let request = URLRequest(url: url)
        return url.host == server.base.host ? authorize(request) : request
    }
}
