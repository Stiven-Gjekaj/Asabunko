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
    /// The file of the values of the settings, or nil to keep them only in memory.
    private let settingsFile: URL?

    private struct Loaded: Decodable {
        let id: String
        let name: String
        let site: String?
        let version: String?
        let paged: Bool
        let imageHeaders: [String: String]
    }

    public init(info: SourceInfo, code: String, settings: URL? = nil, fetcher: @escaping Fetcher) async throws {
        runtime = try JSRuntime(name: "lnreader.\(info.id)", fetcher: fetcher)
        settingsFile = settings
        guard let url = Bundle.module.url(forResource: "lnreader", withExtension: "js") else { throw JSRuntimeError.script("No lnreader.js") }
        try runtime.evaluate(try String(contentsOf: url, encoding: .utf8), url: "lnreader.js")
        // The plugin reads its settings from the storage, so the saved values go in first.
        if let saved = settings.flatMap({ try? Data(contentsOf: $0) }) {
            _ = try await runtime.invoke("(json) => { const v = JSON.parse(json); for (const k of Object.keys(v)) __storage.set(k, v[k]); return true; }",
                                         [String(decoding: saved, as: UTF8.self)])
        }
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

    /// A cover can be a path of the site.
    private func coverURL(_ text: String?) -> URL? {
        guard let text, !text.isEmpty else { return nil }
        if text.hasPrefix("http://") || text.hasPrefix("https://") { return URL(lenient: text) }
        if text.hasPrefix("//") { return URL(lenient: "https:" + text) }
        return site.flatMap { URL(string: text, relativeTo: $0)?.absoluteURL }
    }

    private func page(_ items: [Item]) -> OnlinePage {
        let series = items.map { OnlineSeries(id: $0.path, title: $0.name ?? $0.path, cover: coverURL($0.cover)) }
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
            series: OnlineSeries(id: series.id, title: novel.name ?? series.title, cover: coverURL(novel.cover) ?? series.cover),
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

    // MARK: Filters and settings

    /// The options of the plugin from a list of the JavaScript glue.
    private func specs(_ function: String) async -> [[String: Any]] {
        guard let data = try? await runtime.invoke(function), let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list
    }

    private static func choices(_ spec: [String: Any]) -> [SourceOption.Choice] {
        (spec["options"] as? [[String: Any]] ?? []).map { SourceOption.Choice(label: $0["label"] as? String ?? "", value: $0["value"] as? String ?? "") }
    }

    public func filterOptions() async -> [SourceOption] {
        await specs("__filterSpec").compactMap { spec in
            guard let key = spec["key"] as? String, let type = spec["type"] as? String else { return nil }
            let title = spec["label"] as? String ?? key
            let value = spec["value"]
            let choices = Self.choices(spec)
            switch type {
            case "Text": return SourceOption(id: key, title: title, kind: .text(placeholder: nil), initial: .text(value as? String ?? ""), raw: type)
            case "Switch": return SourceOption(id: key, title: title, kind: .toggle, initial: .toggle(value as? Bool ?? false), raw: type)
            case "Picker":
                guard !choices.isEmpty else { return nil }
                return SourceOption(id: key, title: title, kind: .select(choices), initial: .select((value as? String) ?? choices[0].value), raw: type)
            case "Checkbox":
                return SourceOption(id: key, title: title, kind: .multi(choices, excludable: false),
                                    initial: .multi(included: value as? [String] ?? [], excluded: []), raw: type)
            case "XCheckbox":
                let both = value as? [String: Any]
                return SourceOption(id: key, title: title, kind: .multi(choices, excludable: true),
                                    initial: .multi(included: both?["include"] as? [String] ?? [], excluded: both?["exclude"] as? [String] ?? []), raw: type)
            default: return nil
            }
        }
    }

    /// The value of an option in the form that a plugin reads.
    private static func javaScript(_ value: OptionValue, raw: String) -> Any {
        switch value {
        case let .text(text): text
        case let .toggle(on): on
        case let .select(choice): choice
        case let .multi(included, excluded): raw == "XCheckbox" ? ["include": included, "exclude": excluded] as [String: Any] : included
        case let .sort(index, _): index
        case let .range(from, to): ["from": from ?? NSNull(), "to": to ?? NSNull()] as [String: Any]
        }
    }

    /// The names of the text filters that hold the words of a search, such as the filter "search" of WTR-LAB.
    static let searchFilters: Set<String> = ["search", "keyword", "keywords", "query"]

    public func browse(page number: Int, query: String, filters: [String: OptionValue]) async throws -> OnlinePage {
        let options = await filterOptions()
        // `searchNovels` of LNReader has no filters. A plugin with a text filter for the words of a search gets the
        // words in that filter, and its list does the search with the other filters.
        var filters = filters
        if !query.isEmpty {
            guard let words = options.first(where: { option in
                if case .text = option.kind { Self.searchFilters.contains(option.id) } else { false }
            })
            else { return try await search(query, page: number) }
            filters[words.id] = .text(query)
        }
        var values: [String: Any] = [:]
        for option in options { values[option.id] = Self.javaScript(filters[option.id] ?? option.initial, raw: option.raw) }
        let json = String(decoding: try JSONSerialization.data(withJSONObject: values), as: UTF8.self)
        return page(try await runtime.invoke([Item].self, "__browse", [number, json]))
    }

    public func settingOptions() async -> [SourceOption] {
        await specs("__settingSpec").compactMap { spec in
            guard let key = spec["key"] as? String else { return nil }
            let type = spec["type"] as? String ?? "Text"
            let title = spec["label"] as? String ?? key
            let choices = Self.choices(spec)
            switch type {
            case "Switch": return SourceOption(id: key, title: title, kind: .toggle, initial: .toggle(false), raw: type)
            case "Select" where !choices.isEmpty: return SourceOption(id: key, title: title, kind: .select(choices), initial: .select(choices[0].value), raw: type)
            case "CheckboxGroup": return SourceOption(id: key, title: title, kind: .multi(choices, excludable: false), initial: .multi(included: [], excluded: []), raw: type)
            default: return SourceOption(id: key, title: title, kind: .text(placeholder: nil), initial: .text(""), raw: type)
            }
        }
    }

    public func settingValues() async -> [String: OptionValue] {
        var values: [String: OptionValue] = [:]
        for spec in await specs("__settingSpec") {
            guard let key = spec["key"] as? String else { continue }
            switch spec["value"] {
            case let on as Bool: values[key] = .toggle(on)
            case let list as [String]: values[key] = .multi(included: list, excluded: [])
            case let text as String: values[key] = (spec["type"] as? String) == "Select" ? .select(text) : .text(text)
            case let number as NSNumber: values[key] = .text(number.stringValue)
            default: break
            }
        }
        return values
    }

    public func setSetting(_ id: String, _ value: OptionValue) async {
        let raw = (await settingOptions()).first { $0.id == id }?.raw ?? ""
        let javaScript = Self.javaScript(value, raw: raw)
        guard let json = try? JSONSerialization.data(withJSONObject: [id: javaScript]) else { return }
        _ = try? await runtime.invoke("(json) => { const v = JSON.parse(json); for (const k of Object.keys(v)) __storage.set(k, v[k]); return true; }",
                                      [String(decoding: json, as: UTF8.self)])
        guard let settingsFile else { return }
        var saved = (try? Data(contentsOf: settingsFile)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        saved[id] = javaScript
        if let data = try? JSONSerialization.data(withJSONObject: saved) { try? data.write(to: settingsFile, options: .atomic) }
    }
}
