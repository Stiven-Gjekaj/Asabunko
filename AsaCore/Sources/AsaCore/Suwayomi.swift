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

    private func list(_ type: String, page: Int, query text: String? = nil, filters: [[String: Any]]? = nil) async throws -> OnlinePage {
        // The input goes as one object. Its type name is in the code of the server, and the names of its parts are not needed.
        var input: [String: Any] = ["source": info.id, "type": type, "page": page]
        if let text { input["query"] = text }
        if let filters { input["filters"] = filters }
        let reply = try await server.query(Fetched.self, """
        mutation ($input: FetchSourceMangaInput!) {
          fetchSourceManga(input: $input) { hasNextPage mangas { id title thumbnailUrl } }
        }
        """, ["input": input])
        let items = reply.fetchSourceManga.mangas.map { OnlineSeries(id: String($0.id), title: $0.title, cover: server.absolute($0.thumbnailUrl)) }
        return OnlinePage(items: items, hasMore: reply.fetchSourceManga.hasNextPage)
    }

    public func popular(page: Int) async throws -> OnlinePage { try await list("POPULAR", page: page) }

    // MARK: The filters

    /// A filter of a Mihon source, as the server gives it. A field "default" has another type in each kind,
    /// so each kind has its own name for it.
    private struct Filter: Decodable {
        struct Sort: Decodable { let index: Int; let ascending: Bool }
        let __typename: String
        let name: String?
        let values: [String]?
        let selectDefault: Int?
        let textDefault: String?
        let checkDefault: Bool?
        let triDefault: String?
        let sortDefault: Sort?
        let filters: [Filter]?
    }

    private struct Filters: Decodable {
        struct Source: Decodable { let filters: [Filter] }
        let source: Source
    }

    private static let filterFields = """
    __typename
    ... on HeaderFilter { name }
    ... on SelectFilter { name values selectDefault: default }
    ... on TextFilter { name textDefault: default }
    ... on CheckBoxFilter { name checkDefault: default }
    ... on TriStateFilter { name triDefault: default }
    ... on SortFilter { name values sortDefault: default { index ascending } }
    """

    /// The filters of the source as options. The ID of an option is the position of its filter, and "3.1" is the
    /// filter 1 in the group 3. A group of checks is one choice of many values.
    public func filterOptions() async -> [SourceOption] {
        guard let reply = try? await server.query(Filters.self, """
        query ($id: LongString!) { source(id: $id) { filters { \(Self.filterFields) ... on GroupFilter { name filters { \(Self.filterFields) } } } } }
        """, ["id": info.id]) else { return [] }
        var options: [SourceOption] = []
        for (index, filter) in reply.source.filters.enumerated() {
            if filter.__typename == "GroupFilter" {
                let children = filter.filters ?? []
                if !children.isEmpty, children.allSatisfy({ $0.__typename == "CheckBoxFilter" || $0.__typename == "TriStateFilter" }) {
                    let choices = children.enumerated().map { SourceOption.Choice(label: $1.name ?? "", value: String($0)) }
                    let included = children.enumerated().filter { $1.checkDefault == true || $1.triDefault == "INCLUDE" }.map { String($0.offset) }
                    let excluded = children.enumerated().filter { $1.triDefault == "EXCLUDE" }.map { String($0.offset) }
                    // The kind of each child, one letter for each: "c" for a check and "t" for a three-state.
                    let kinds = children.map { $0.__typename == "TriStateFilter" ? "t" : "c" }.joined()
                    options.append(SourceOption(id: String(index), title: filter.name ?? "", kind: .multi(choices, excludable: kinds.contains("t")),
                                                initial: .multi(included: included, excluded: excluded), raw: "group:" + kinds))
                } else {
                    for (inner, child) in children.enumerated() { if let option = Self.option(child, id: "\(index).\(inner)") { options.append(option) } }
                }
            } else if let option = Self.option(filter, id: String(index)) {
                options.append(option)
            }
        }
        return options
    }

    private static func option(_ filter: Filter, id: String) -> SourceOption? {
        let name = filter.name ?? ""
        let choices = (filter.values ?? []).enumerated().map { SourceOption.Choice(label: $1, value: String($0)) }
        switch filter.__typename {
        case "SelectFilter" where !choices.isEmpty:
            return SourceOption(id: id, title: name, kind: .select(choices), initial: .select(String(filter.selectDefault ?? 0)), raw: "select")
        case "TextFilter":
            return SourceOption(id: id, title: name, kind: .text(placeholder: nil), initial: .text(filter.textDefault ?? ""), raw: "text")
        case "CheckBoxFilter":
            return SourceOption(id: id, title: name, kind: .toggle, initial: .toggle(filter.checkDefault ?? false), raw: "check")
        case "TriStateFilter":
            let states = [("Any", "IGNORE"), ("Include", "INCLUDE"), ("Exclude", "EXCLUDE")].map { SourceOption.Choice(label: $0, value: $1) }
            return SourceOption(id: id, title: name, kind: .select(states), initial: .select(filter.triDefault ?? "IGNORE"), raw: "tri")
        case "SortFilter" where !choices.isEmpty:
            return SourceOption(id: id, title: name, kind: .sort(choices, canAscend: true),
                                initial: .sort(index: filter.sortDefault?.index ?? 0, ascending: filter.sortDefault?.ascending ?? false), raw: "sort")
        default:
            return nil
        }
    }

    /// The changes of the filters for `fetchSourceManga`. Only a filter that the user changed goes.
    static func changes(_ values: [String: OptionValue], options: [SourceOption]) -> [[String: Any]] {
        var changes: [[String: Any]] = []
        for option in options {
            guard let value = values[option.id], value != option.initial else { continue }
            let path = option.id.split(separator: ".").compactMap { Int($0) }
            func wrap(_ change: [String: Any]) -> [String: Any] {
                // A filter in a group goes in a change of its group.
                guard path.count == 2 else { return ["position": path[0]].merging(change) { $1 } }
                return ["position": path[0], "groupChange": ["position": path[1]].merging(change) { $1 }]
            }
            switch value {
            case let .select(choice) where option.raw == "tri": changes.append(wrap(["triState": choice]))
            case let .select(choice): changes.append(wrap(["selectState": Int(choice) ?? 0]))
            case let .text(text): changes.append(wrap(["textState": text]))
            case let .toggle(on): changes.append(wrap(["checkBoxState": on]))
            case let .sort(index, ascending): changes.append(wrap(["sortState": ["index": index, "ascending": ascending]]))
            case let .multi(included, excluded):
                let kinds = Array(option.raw.dropFirst("group:".count))
                guard case let .multi(start, startExcluded) = option.initial, case let .multi(choices, _) = option.kind else { continue }
                for choice in choices {
                    guard let child = Int(choice.value), kinds.indices.contains(child) else { continue }
                    let state = included.contains(choice.value) ? "INCLUDE" : excluded.contains(choice.value) ? "EXCLUDE" : "IGNORE"
                    let before = start.contains(choice.value) ? "INCLUDE" : startExcluded.contains(choice.value) ? "EXCLUDE" : "IGNORE"
                    guard state != before else { continue }
                    let inner: [String: Any] = kinds[child] == "t" ? ["position": child, "triState": state] : ["position": child, "checkBoxState": state == "INCLUDE"]
                    changes.append(["position": path[0], "groupChange": inner])
                }
            case .range:
                continue
            }
        }
        return changes
    }

    public func browse(page: Int, query: String, filters: [String: OptionValue]) async throws -> OnlinePage {
        guard !filters.isEmpty else { return query.isEmpty ? try await popular(page: page) : try await search(query, page: page) }
        let changes = Self.changes(filters, options: await filterOptions())
        return try await list("SEARCH", page: page, query: query, filters: changes)
    }

    // MARK: The settings

    /// A preference of a Mihon source. Each kind has its own names for its value and its default.
    private struct Preference: Decodable {
        let __typename: String
        let key: String?
        let title: String?
        let visible: Bool?
        let on: Bool?
        let onDefault: Bool?
        let text: String?
        let textDefault: String?
        let choice: String?
        let choiceDefault: String?
        let choices: [String]?
        let choicesDefault: [String]?
        let entries: [String]?
        let entryValues: [String]?
    }

    private struct Preferences: Decodable {
        struct Source: Decodable { let preferences: [Preference] }
        let source: Source
    }

    private func preferences() async -> [Preference] {
        (try? await server.query(Preferences.self, """
        query ($id: LongString!) { source(id: $id) { preferences {
          __typename
          ... on SwitchPreference { key title visible on: currentValue onDefault: default }
          ... on CheckBoxPreference { key title visible on: currentValue onDefault: default }
          ... on EditTextPreference { key title visible text: currentValue textDefault: default }
          ... on ListPreference { key title visible choice: currentValue choiceDefault: default entries entryValues }
          ... on MultiSelectListPreference { key title visible choices: currentValue choicesDefault: default entries entryValues }
        } } }
        """, ["id": info.id]))?.source.preferences ?? []
    }

    /// The settings of the source. The ID of a setting is the position of its preference, which the server needs to change it.
    public func settingOptions() async -> [SourceOption] {
        (await preferences()).enumerated().compactMap { index, preference in
            guard preference.visible != false else { return nil }
            let id = String(index), title = preference.title ?? preference.key ?? ""
            let choices = zip(preference.entries ?? [], preference.entryValues ?? []).map { SourceOption.Choice(label: $0, value: $1) }
            switch preference.__typename {
            case "SwitchPreference", "CheckBoxPreference":
                return SourceOption(id: id, title: title, kind: .toggle, initial: .toggle(preference.onDefault ?? false), raw: preference.__typename)
            case "EditTextPreference":
                return SourceOption(id: id, title: title, kind: .text(placeholder: nil), initial: .text(preference.textDefault ?? ""), raw: preference.__typename)
            case "ListPreference" where !choices.isEmpty:
                return SourceOption(id: id, title: title, kind: .select(choices), initial: .select(preference.choiceDefault ?? choices[0].value), raw: preference.__typename)
            case "MultiSelectListPreference" where !choices.isEmpty:
                return SourceOption(id: id, title: title, kind: .multi(choices, excludable: false),
                                    initial: .multi(included: preference.choicesDefault ?? [], excluded: []), raw: preference.__typename)
            default:
                return nil
            }
        }
    }

    public func settingValues() async -> [String: OptionValue] {
        var values: [String: OptionValue] = [:]
        for (index, preference) in (await preferences()).enumerated() {
            let id = String(index)
            switch preference.__typename {
            case "SwitchPreference", "CheckBoxPreference": if let on = preference.on { values[id] = .toggle(on) }
            case "EditTextPreference": if let text = preference.text { values[id] = .text(text) }
            case "ListPreference": if let choice = preference.choice { values[id] = .select(choice) }
            case "MultiSelectListPreference": if let choices = preference.choices { values[id] = .multi(included: choices, excluded: []) }
            default: break
            }
        }
        return values
    }

    public func setSetting(_ id: String, _ value: OptionValue) async {
        guard let position = Int(id), let option = (await settingOptions()).first(where: { $0.id == id }) else { return }
        var change: [String: Any] = ["position": position]
        switch value {
        case let .toggle(on): change[option.raw == "CheckBoxPreference" ? "checkBoxState" : "switchState"] = on
        case let .text(text): change["editTextState"] = text
        case let .select(choice): change["listState"] = choice
        case let .multi(included, _): change["multiSelectState"] = included
        case .sort, .range: return
        }
        struct Changed: Decodable { struct Payload: Decodable { let clientMutationId: String? }; let updateSourcePreference: Payload? }
        _ = try? await server.query(Changed.self, """
        mutation ($input: UpdateSourcePreferenceInput!) { updateSourcePreference(input: $input) { clientMutationId } }
        """, ["input": ["source": info.id, "change": change]])
    }
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
