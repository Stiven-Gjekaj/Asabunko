import Foundation

/// The list of LNReader plugins, such as plugins.min.json.
public enum LNReaderIndex {
    private struct Item: Decodable {
        let id: String
        let name: String
        let site: String?
        let lang: String?
        let version: String
        let url: String
        let iconUrl: String?
    }

    public static func parse(_ data: Data) throws -> [SourceInfo] {
        try JSONDecoder().decode([Item].self, from: data).compactMap { item in
            guard let code = URL(lenient: item.url) else { return nil }
            return SourceInfo(
                id: item.id, name: item.name,
                language: (item.lang ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\u{200E}\u{200F}").union(.whitespaces)),
                version: item.version, icon: item.iconUrl.flatMap { URL(lenient: $0) }, code: code, novels: true
            )
        }
    }
}

/// One LNReader plugin in its own JavaScript context.
public final class LNReaderPlugin: OnlineSource, @unchecked Sendable {
    public let info: SourceInfo
    public let site: URL?
    private let runtime: JSRuntime
    private let paged: Bool
    private let imageHeaders: [String: String]

    private struct Loaded: Decodable {
        let id: String
        let name: String
        let site: String?
        let version: String?
        let paged: Bool
        let imageHeaders: [String: String]
    }

    public init(info: SourceInfo, code: String, fetcher: @escaping Fetcher) async throws {
        runtime = try JSRuntime(name: "lnreader.\(info.id)", fetcher: fetcher)
        guard let url = Bundle.module.url(forResource: "lnreader", withExtension: "js") else { throw JSRuntimeError.script("No lnreader.js") }
        try runtime.evaluate(try String(contentsOf: url, encoding: .utf8), url: "lnreader.js")
        let loaded = try await runtime.invoke(Loaded.self, "__loadPlugin", [code])
        self.info = info
        self.site = loaded.site.flatMap { URL(lenient: $0) }
        self.paged = loaded.paged
        self.imageHeaders = loaded.imageHeaders
    }

    public var canShowLatest: Bool { true }

    private struct Item: Decodable {
        let name: String?
        let path: String
        let cover: String?
    }

    private func page(_ items: [Item]) -> OnlinePage {
        let series = items.map { OnlineSeries(id: $0.path, title: $0.name ?? $0.path, cover: $0.cover.flatMap { URL(lenient: $0) }) }
        // A plugin gives an empty page at the end of its list.
        return OnlinePage(items: series, hasMore: !series.isEmpty)
    }

    public func popular(page number: Int) async throws -> OnlinePage {
        page(try await runtime.invoke([Item].self, "(page) => plugin.popularNovels(page, { showLatestNovels: false, filters: __filters() })", [number]))
    }

    public func latest(page number: Int) async throws -> OnlinePage {
        page(try await runtime.invoke([Item].self, "(page) => plugin.popularNovels(page, { showLatestNovels: true, filters: __filters() })", [number]))
    }

    public func search(_ query: String, page number: Int) async throws -> OnlinePage {
        page(try await runtime.invoke([Item].self, "(q, page) => plugin.searchNovels(q, page)", [query, number]))
    }

    private struct Novel: Decodable {
        struct Chapter: Decodable {
            let name: String?
            let path: String
            let releaseTime: String?
            let chapterNumber: Double?
            let page: String?
        }
        let name: String?
        let path: String?
        let cover: String?
        let summary: String?
        let author: String?
        let status: String?
        let genres: String?
        let chapters: [Chapter]?
        let totalPages: Int?
    }

    private struct PageOfChapters: Decodable { let chapters: [Novel.Chapter] }

    public func details(of series: OnlineSeries) async throws -> OnlineDetails {
        let novel = try await runtime.invoke(Novel.self, "(path) => plugin.parseNovel(path)", [series.id])
        var chapters = novel.chapters ?? []
        // A paged plugin gives the chapters of one page at a time.
        if paged, let total = novel.totalPages, total > 1 || chapters.isEmpty {
            chapters = []
            for number in 1...max(total, 1) {
                let part = try await runtime.invoke(PageOfChapters.self, "(path, page) => plugin.parsePage(path, page)", [series.id, String(number)])
                chapters += part.chapters
            }
        }
        let genres = (novel.genres ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return OnlineDetails(
            series: OnlineSeries(id: series.id, title: novel.name ?? series.title, cover: novel.cover.flatMap { URL(lenient: $0) } ?? series.cover),
            author: novel.author?.nonEmpty, summary: novel.summary?.nonEmpty, status: novel.status?.nonEmpty, genres: genres,
            chapters: chapters.enumerated().map { index, chapter in
                OnlineChapter(id: chapter.path, title: chapter.name?.nonEmpty ?? "Chapter \(index + 1)", number: chapter.chapterNumber, date: chapter.releaseTime)
            }
        )
    }

    public func content(of chapter: OnlineChapter, in series: OnlineSeries) async throws -> ChapterContent {
        .html(try await runtime.invoke(String.self, "(path) => plugin.parseChapter(path)", [chapter.id]))
    }

    /// The full URL of a path of the site, for a link in the browser.
    public func webURL(of path: String, novel: Bool) async -> URL? {
        (try? await runtime.invoke(String.self, "(path, isNovel) => __resolve(path, isNovel)", [path, novel])).flatMap { URL(lenient: $0) }
    }

    public func imageRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        for (key, value) in imageHeaders { request.setValue(value, forHTTPHeaderField: key) }
        return request
    }
}
