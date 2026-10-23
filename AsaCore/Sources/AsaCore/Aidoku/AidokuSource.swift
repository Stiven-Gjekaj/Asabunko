import Foundation

/// The list of Aidoku sources, such as index.min.json of Aidoku Community.
public enum AidokuIndex {
    private struct List: Decodable {
        let sources: [Item]
    }

    private struct Item: Decodable {
        let id: String
        let name: String
        let version: Int
        let iconURL: String?
        let downloadURL: String?
        let languages: [String]?
        let contentRating: Int?
        // The form of the lists before Aidoku 0.7.
        let file: String?
        let icon: String?
        let lang: String?
        let nsfw: Int?
    }

    /// The links of the list are relative to the folder of `url`.
    public static func parse(_ data: Data, url: URL) throws -> [SourceInfo] {
        let decoder = JSONDecoder()
        let items: [Item]
        if let list = try? decoder.decode(List.self, from: data) {
            items = list.sources
        } else {
            items = try decoder.decode([Item].self, from: data)
        }
        let folder = url.deletingLastPathComponent()
        return items.compactMap { item in
            guard let download = item.downloadURL ?? item.file.map({ "sources/" + $0 }),
                  let code = URL(string: download, relativeTo: folder)?.absoluteURL else { return nil }
            let icon = (item.iconURL ?? item.icon.map { "icons/" + $0 }).flatMap { URL(string: $0, relativeTo: folder)?.absoluteURL }
            let languages = item.languages ?? item.lang.map { [$0] } ?? []
            let rating = item.contentRating ?? item.nsfw ?? 0
            // Aidoku has sources of novels too. Their names say it.
            let novels = (item.id + " " + item.name).lowercased().contains("novel")
            return SourceInfo(
                id: item.id, name: item.name, language: languages.count > 1 ? "Multi" : (languages.first ?? ""),
                version: String(item.version), icon: icon, code: code, novels: novels, adult: rating >= 2
            )
        }
    }
}

/// The files of an .aix package: a ZIP with Payload/main.wasm, Payload/source.json, and other files.
struct AidokuPackage {
    struct Manifest: Decodable {
        struct Info: Decodable {
            let id: String
            let name: String
            let url: String?
            let urls: [String]?
            let languages: [String]?
        }
        struct Listing: Decodable {
            let id: String
            let name: String?
            let kind: UInt64?
            init(from decoder: Decoder) throws {
                if let text = try? decoder.singleValueContainer().decode(String.self) {
                    id = text; name = nil; kind = nil
                } else {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    id = try c.decode(String.self, forKey: .id)
                    name = try c.decodeIfPresent(String.self, forKey: .name)
                    kind = try c.decodeIfPresent(UInt64.self, forKey: .kind)
                }
            }
            private enum CodingKeys: String, CodingKey { case id, name, kind }
        }
        struct Config: Decodable {
            let languageSelectType: String?
            let allowsBaseUrlSelect: Bool?
        }
        let info: Info
        let listings: [Listing]?
        let config: Config?
    }

    let wasm: Data
    let manifest: Manifest
    let settings: Data?
    let filters: Data?

    init(_ file: URL) throws {
        var wasm: Data?, manifest: Data?, settings: Data?, filters: Data?
        try ArchiveReader.forEachFile(in: file) { entry, read in
            switch entry.path.hasPrefix("Payload/") ? String(entry.path.dropFirst(8)) : entry.path {
            case "main.wasm": wasm = try read()
            case "source.json": manifest = try read()
            case "settings.json": settings = try read()
            case "filters.json": filters = try read()
            default: break
            }
        }
        guard let wasm, let manifest else { throw AidokuHost.Failure.missing("main.wasm or source.json") }
        self.wasm = wasm
        self.manifest = try JSONDecoder().decode(Manifest.self, from: manifest)
        self.settings = settings
        self.filters = filters
    }

    /// The first values of the settings: the languages, the base URL, and the default of each setting of settings.json.
    var initialDefaults: [String: Data] {
        var values: [String: Data] = [:]
        func put(_ key: String, _ write: (inout PostcardWriter) -> Void) {
            var w = PostcardWriter()
            write(&w)
            values[key] = w.data
        }
        let languages = manifest.info.languages ?? []
        let single = manifest.config?.languageSelectType != "multi"
        put("languages") { w in w.list(single ? Array(languages.prefix(1)) : languages) { $0.string($1) } }
        if let url = manifest.info.urls?.first ?? manifest.info.url {
            put("url") { $0.string(url) }
        }
        guard let settings, let groups = try? JSONSerialization.jsonObject(with: settings) as? [[String: Any]] else { return values }
        func visit(_ setting: [String: Any]) {
            for child in setting["items"] as? [[String: Any]] ?? [] { visit(child) }
            guard let key = setting["key"] as? String, let value = setting["default"] else { return }
            switch (setting["type"] as? String, value) {
            case let ("switch", flag as Bool): put(key) { $0.bool(flag) }
            case let ("segment", number as Int): put(key) { $0.signed(number) }
            case let ("stepper", number as Double): put(key) { $0.f32(Float(number)) }
            case let (_, text as String): put(key) { $0.string(text) }
            case let (_, list as [String]): put(key) { w in w.list(list) { $0.string($1) } }
            default: break
            }
        }
        groups.forEach(visit)
        return values
    }
}

/// One Aidoku source in its own WebAssembly instance.
public final class AidokuSource: OnlineSource, @unchecked Sendable {
    public let info: SourceInfo
    private let host: AidokuHost
    private let listings: [Aidoku.Listing]
    private let baseURL: URL?
    private let filterList: [SourceOption]
    private let settingList: [SourceOption]
    /// The full data of each series and chapter that the source gave, because a source can need more than the key.
    private var known: [String: Aidoku.Manga] = [:]
    private var chapters: [String: Aidoku.Chapter] = [:]
    private let lock = NSLock()

    /// `package` is the .aix file. `settings` is the file of the values of the settings.
    public init(info: SourceInfo, package file: URL, settings: URL?, fetcher: @escaping Fetcher) throws {
        let package = try AidokuPackage(file)
        self.info = info
        let host = try AidokuHost(name: info.id, wasm: package.wasm, defaults: AidokuDefaults(file: settings, initial: package.initialDefaults), fetcher: fetcher)
        self.host = host
        var listings = (package.manifest.listings ?? []).map { Aidoku.Listing(id: $0.id, name: $0.name ?? $0.id, kind: $0.kind ?? 0) }
        if listings.isEmpty, host.exports.contains("get_listings"), let dynamic = try? host.queue.sync(execute: { try host.call("get_listings", []) }) {
            var r = PostcardReader(dynamic)
            listings = (try? r.list { try Aidoku.Listing.read(&$0) }) ?? []
        }
        self.listings = listings
        self.baseURL = (package.manifest.info.urls?.first ?? package.manifest.info.url).flatMap { URL(string: $0) }
        filterList = AidokuOptions.filters(package.filters)
        settingList = AidokuOptions.settings(package.settings)
    }

    public func filterOptions() async -> [SourceOption] { filterList }

    public func browse(page number: Int, query: String, filters: [String: OptionValue]) async throws -> OnlinePage {
        try await browse(query.isEmpty ? nil : query, page: number, filters: AidokuOptions.encode(filters, filters: filterList))
    }

    public func settingOptions() async -> [SourceOption] { settingList }

    public func settingValues() async -> [String: OptionValue] {
        var values: [String: OptionValue] = [:]
        for setting in settingList {
            values[setting.id] = host.defaults[setting.id].flatMap { AidokuOptions.decodeSetting($0, of: setting) } ?? setting.initial
        }
        return values
    }

    public func setSetting(_ id: String, _ value: OptionValue) async {
        guard let setting = settingList.first(where: { $0.id == id }) else { return }
        host.defaults[id] = AidokuOptions.encodeSetting(value, of: setting)
    }

    /// The listing for popular series, and the listing for the latest ones, by their names.
    private func listing(_ words: [String]) -> Aidoku.Listing? {
        listings.first { listing in words.contains { (listing.id + " " + listing.name).lowercased().contains($0) } }
    }

    private var popularListing: Aidoku.Listing? { listing(["popular", "hot", "trend", "top", "rank"]) }
    private var latestListing: Aidoku.Listing? { listing(["latest", "update", "recent", "new"]) }

    public var canShowLatest: Bool { host.exports.contains("get_manga_list") && latestListing != nil }

    private func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            host.queue.async { continuation.resume(with: Result { try body() }) }
        }
    }

    private func page(_ data: Data) throws -> OnlinePage {
        var r = PostcardReader(data)
        let result = try Aidoku.MangaPageResult.read(&r)
        lock.withLock { for manga in result.entries { known[manga.key] = manga } }
        return OnlinePage(
            items: result.entries.map { OnlineSeries(id: $0.key, title: $0.title, cover: $0.cover.flatMap { URL(lenient: $0) }) },
            hasMore: result.hasNextPage
        )
    }

    private func list(_ listing: Aidoku.Listing, page number: Int) async throws -> OnlinePage {
        var w = PostcardWriter()
        listing.write(&w)
        let bytes = w.data
        return try page(try await run { [host] in try host.call("get_manga_list", [bytes, Int32(number)]) })
    }

    /// The search of the source. The query is raw UTF-8. With no filters, the list of filters is empty.
    private func browse(_ query: String?, page number: Int, filters: Data = Data([0x00])) async throws -> OnlinePage {
        let query = Data((query ?? "").utf8)
        return try page(try await run { [host] in try host.call("get_search_manga_list", [query, Int32(number), filters]) })
    }

    public func popular(page number: Int) async throws -> OnlinePage {
        if let popularListing, host.exports.contains("get_manga_list") { return try await list(popularListing, page: number) }
        return try await browse(nil, page: number)
    }

    public func latest(page number: Int) async throws -> OnlinePage {
        guard let latestListing else { return try await browse(nil, page: number) }
        return try await list(latestListing, page: number)
    }

    public func search(_ query: String, page number: Int) async throws -> OnlinePage {
        try await browse(query, page: number)
    }

    private func manga(_ series: OnlineSeries) -> Aidoku.Manga {
        lock.withLock { known[series.id] } ?? Aidoku.Manga(key: series.id, title: series.title, cover: series.cover?.absoluteString)
    }

    public func details(of series: OnlineSeries) async throws -> OnlineDetails {
        var w = PostcardWriter()
        manga(series).write(&w)
        let bytes = w.data
        let data = try await run { [host] in try host.call("get_manga_update", [bytes, true, true]) }
        var r = PostcardReader(data)
        let manga = try Aidoku.Manga.read(&r)
        var stored = manga
        stored.chapters = nil
        // A source gives the newest chapter first.
        let list = (manga.chapters ?? []).reversed()
        lock.withLock {
            known[manga.key] = stored
            for chapter in list { chapters[chapter.key] = chapter }
        }
        let people = (manga.authors ?? []) + (manga.artists ?? []).filter { !(manga.authors ?? []).contains($0) }
        return OnlineDetails(
            series: OnlineSeries(id: manga.key, title: manga.title, cover: manga.cover.flatMap { URL(lenient: $0) } ?? series.cover),
            author: people.joined(separator: ", ").nonEmpty, summary: manga.description?.nonEmpty, status: manga.statusName,
            genres: manga.tags ?? [],
            chapters: list.filter { !$0.locked }.map { chapter in
                OnlineChapter(
                    id: chapter.key, title: chapter.displayTitle, number: chapter.chapterNumber.map(Double.init),
                    date: chapter.dateUploaded.map { Date(timeIntervalSince1970: TimeInterval($0)).formatted(.iso8601.year().month().day()) },
                    group: chapter.scanlators?.joined(separator: ", ")
                )
            }
        )
    }

    public func content(of chapter: OnlineChapter, in series: OnlineSeries) async throws -> ChapterContent {
        if lock.withLock({ chapters[chapter.id] }) == nil { _ = try await details(of: series) }
        var w = PostcardWriter()
        manga(series).write(&w)
        let mangaBytes = w.data
        var c = PostcardWriter()
        (lock.withLock { chapters[chapter.id] } ?? Aidoku.Chapter(key: chapter.id, title: chapter.title)).write(&c)
        let chapterBytes = c.data
        let host = host
        let hasImageRequest = host.exports.contains("get_image_request")
        return try await run { [self] in
            let data = try host.call("get_page_list", [mangaBytes, chapterBytes])
            var r = PostcardReader(data)
            let pages = try r.list { try Aidoku.Page.read(&$0) }
            let texts = pages.compactMap { page -> String? in if case let .text(text) = page.content { return text }; return nil }
            if !texts.isEmpty, texts.count == pages.count { return .html(Self.html(fromMarkdown: texts.joined(separator: "\n\n"))) }
            return .pages(pages.compactMap { page in
                guard case let .url(url, context) = page.content, let target = URL(lenient: url) else { return nil }
                return hasImageRequest ? (try? imageRequest(url: url, context: context)) ?? plainRequest(target) : plainRequest(target)
            })
        }
    }

    /// The request of a page from the source, with its headers, from get_image_request. The caller is on the queue.
    private func imageRequest(url: String, context: [String: String]?) throws -> URLRequest? {
        var w = PostcardWriter()
        w.string(url)
        var arguments: [Any] = [w.data]
        if let context {
            var m = PostcardWriter()
            Aidoku.writeMap(context, &m)
            arguments.append(m.data)
        } else {
            arguments.append(Int32(-1))
        }
        let data = try host.call("get_image_request", arguments)
        var r = PostcardReader(data)
        let rid = Int32(truncatingIfNeeded: try r.signed())
        defer { host.destroy(rid) }
        guard case let .request(request)? = host.item(rid), let target = request.url else { return nil }
        var result = URLRequest(url: target)
        result.httpMethod = request.method
        for (key, value) in request.headers { result.setValue(value, forHTTPHeaderField: key) }
        return result
    }

    private func plainRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let baseURL { request.setValue(baseURL.absoluteString + "/", forHTTPHeaderField: "Referer") }
        return request
    }

    /// A cover with the referer of the site, which many sites ask for.
    public func imageRequest(_ url: URL) -> URLRequest { plainRequest(url) }

    /// The text of a novel source is Markdown. Paragraphs, headings, bold, and italic are enough for a chapter.
    static func html(fromMarkdown text: String) -> String {
        text.components(separatedBy: "\n\n").map { block -> String in
            var line = XHTML.escape(block.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !line.isEmpty else { return "" }
            line = line.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<b>$1</b>", options: .regularExpression)
            line = line.replacingOccurrences(of: "\\*(.+?)\\*", with: "<i>$1</i>", options: .regularExpression)
            line = line.replacingOccurrences(of: "\n", with: "<br/>")
            if line.hasPrefix("### ") { return "<h4>\(line.dropFirst(4))</h4>" }
            if line.hasPrefix("## ") { return "<h3>\(line.dropFirst(3))</h3>" }
            if line.hasPrefix("# ") { return "<h2>\(line.dropFirst(2))</h2>" }
            return "<p>\(line)</p>"
        }.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
