import AsaCore
import Foundation

/// The fetcher of the JavaScript and WebAssembly sources: the session of the app.
let appFetcher: Fetcher = { request in
    var request = request
    if request.value(forHTTPHeaderField: "User-Agent") == nil { request.setValue(Network.userAgent, forHTTPHeaderField: "User-Agent") }
    let (data, response) = try await Network.session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    BrowserChecks.inspect(http, data: data)
    return (data, http)
}

/// Why a chapter of a novel cannot open.
enum ChapterFault: LocalizedError {
    case missing
    case sourceGone
    case notText
    case notPages

    var errorDescription: String? {
        switch self {
        case .missing: "The file of the chapter is not on this device."
        case .sourceGone: "The source of this book is not installed. Add its list again in Settings, Sources."
        case .notText: "The source gave images for this chapter, not text."
        case .notPages: "The source gave text for this chapter, not pages."
        }
    }
}

/// The sources that the app has loaded in this session, by the ID of their installation.
/// A source runs a JavaScript context or a WebAssembly instance, so the sources that the user did not
/// use for the longest time leave the memory when there are many.
@MainActor
final class LoadedSources {
    static let shared = LoadedSources()
    private var sources: [String: OnlineSource] = [:]
    /// The IDs from the last used to the most recently used.
    private var order: [String] = []
    /// The loads that run now, so that two screens that ask for one source get one runtime.
    var loading: [String: Task<OnlineSource, Error>] = [:]
    static let limit = 24

    func get(_ id: String) -> OnlineSource? {
        guard let source = sources[id] else { return nil }
        order.removeAll { $0 == id }
        order.append(id)
        return source
    }

    func set(_ id: String, _ source: OnlineSource) {
        sources[id] = source
        order.removeAll { $0 == id }
        order.append(id)
        while order.count > Self.limit { sources[order.removeFirst()] = nil }
    }

    func remove(_ id: String) {
        sources[id] = nil
        order.removeAll { $0 == id }
    }
}

extension AppModel {
    private var pluginsFolder: URL { Self.defaultRoot.appendingPathComponent("Sources", isDirectory: true) }

    private func codeFile(of installed: InstalledSource) -> URL {
        let safe = installed.info.id.replacingOccurrences(of: "/", with: "_")
        return pluginsFolder.appendingPathComponent(installed.list.uuidString).appendingPathComponent(safe + ".code")
    }

    /// The fetcher of a server with an account: it adds the user name and the password of its line.
    nonisolated static func fetcher(for link: SourceLink) -> Fetcher {
        { request in
            var request = request
            let signed = AppModel.request(request.url!, source: link)
            if let value = signed.value(forHTTPHeaderField: "Authorization") { request.setValue(value, forHTTPHeaderField: "Authorization") }
            return try await appFetcher(request)
        }
    }

    /// The sources in a list of the source list.
    func sources(in link: SourceLink) async throws -> [SourceInfo] {
        switch link.kind {
        case .lnreader:
            return try LNReaderIndex.parse(try await Network.data(for: AppModel.request(link.url, source: link)))
        case .suwayomi:
            return try await SuwayomiServer(base: link.url, fetcher: Self.fetcher(for: link)).sources()
        case .aidoku:
            return try AidokuIndex.parse(try await Network.data(for: AppModel.request(link.url, source: link)), url: link.url)
        case .paperback:
            // The URL of a repository can be its folder or its versioning.json.
            let url = link.url.pathExtension == "json" ? link.url : link.url.appendingPathComponent("versioning.json")
            return try PaperbackIndex.parse(try await Network.data(for: AppModel.request(url, source: link)), url: url)
        default:
            return []
        }
    }

    private func link(of installed: InstalledSource) -> SourceLink? {
        library.sources.first { $0.id == installed.list }
    }

    func isInstalled(_ info: SourceInfo, from link: SourceLink) -> Bool {
        library.installed.contains { $0.list == link.id && $0.info.id == info.id }
    }

    /// Downloads the code of a source and keeps it on the device.
    func install(_ info: SourceInfo, from link: SourceLink) async throws {
        let installed = InstalledSource(list: link.id, info: info)
        // A source of a server runs on the server, so it has no code on the device.
        if link.kind != .suwayomi {
            let code = try await Network.data(for: URLRequest(url: info.code))
            let file = codeFile(of: installed)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try code.write(to: file, options: .atomic)
        }
        LoadedSources.shared.remove(installed.id)
        changeLibrary { library in
            library.installed.removeAll { $0.id == installed.id }
            library.installed.append(installed)
        }
    }

    func uninstall(_ installed: InstalledSource) {
        try? FileManager.default.removeItem(at: codeFile(of: installed))
        try? FileManager.default.removeItem(at: codeFile(of: installed).deletingPathExtension().appendingPathExtension("settings.json"))
        LoadedSources.shared.remove(installed.id)
        changeLibrary { $0.installed.removeAll { $0.id == installed.id } }
    }

    func kind(of installed: InstalledSource) -> SourceKind? {
        library.sources.first { $0.id == installed.list }?.kind
    }

    /// The source, loaded one time in each session.
    func load(_ installed: InstalledSource) async throws -> OnlineSource {
        let loaded = LoadedSources.shared
        if let source = loaded.get(installed.id) { return source }
        if let running = loaded.loading[installed.id] { return try await running.value }
        let task = Task { try await makeSource(installed) }
        loaded.loading[installed.id] = task
        defer { loaded.loading[installed.id] = nil }
        let source = try await task.value
        loaded.set(installed.id, source)
        return source
    }

    private func makeSource(_ installed: InstalledSource) async throws -> OnlineSource {
        let source: OnlineSource
        switch kind(of: installed) {
        case .lnreader:
            let file = codeFile(of: installed)
            let code = try Data(contentsOf: file)
            source = try await LNReaderPlugin(
                info: installed.info, code: String(decoding: code, as: UTF8.self),
                settings: file.deletingPathExtension().appendingPathExtension("settings.json"), fetcher: appFetcher
            )
        case .paperback:
            let file = codeFile(of: installed)
            let code = String(decoding: try Data(contentsOf: file), as: UTF8.self)
            source = try await PaperbackExtension(
                info: installed.info, code: code, stateFile: file.deletingPathExtension().appendingPathExtension("settings.json"),
                userAgent: Network.userAgent, fetcher: appFetcher
            )
        case .aidoku:
            let file = codeFile(of: installed)
            let settings = file.deletingPathExtension().appendingPathExtension("settings.json")
            source = try await Task.detached {
                try AidokuSource(info: installed.info, package: file, settings: settings, fetcher: appFetcher)
            }.value
        case .suwayomi:
            guard let link = link(of: installed) else { throw SuwayomiServer.Failure.graphQL("The server is not in the source list.") }
            source = SuwayomiSource(info: installed.info, server: SuwayomiServer(base: link.url, fetcher: Self.fetcher(for: link))) { request in
                var request = request
                if let value = AppModel.request(request.url!, source: link).value(forHTTPHeaderField: "Authorization") {
                    request.setValue(value, forHTTPHeaderField: "Authorization")
                }
                return request
            }
        default:
            throw JSRuntimeError.script("Asabunko cannot run this kind of source.")
        }
        return source
    }

    /// The source of a book, when the book comes from an installed source.
    func installed(for book: Book) -> InstalledSource? {
        guard let origin = book.origin else { return nil }
        return library.installed.first { $0.list == origin.list && $0.info.id == origin.source }
    }

    // MARK: Online books

    /// Adds a series or a novel of a source to the library, with its chapters and its cover.
    /// With `listed` false, the book only keeps the place of the user. It is not in the read list.
    @discardableResult
    func add(_ details: OnlineDetails, from installed: InstalledSource, listed: Bool) async throws -> Book {
        let origin = BookOrigin(list: installed.list, source: installed.info.id, series: details.series.id)
        if let book = library.book(from: origin) {
            if listed && !book.listed { update(book.id) { $0.listed = true } }
            return self.book(book.id) ?? book
        }
        // A second tap while the first add runs gets the same book.
        if let running = adding[origin] {
            let book = try await running.value
            if listed && !book.listed { update(book.id) { $0.listed = true } }
            return self.book(book.id) ?? book
        }
        let task = Task { try await addNew(details, origin: origin, from: installed, listed: listed) }
        adding[origin] = task
        defer { adding[origin] = nil }
        return try await task.value
    }

    private func addNew(_ details: OnlineDetails, origin: BookOrigin, from installed: InstalledSource, listed: Bool) async throws -> Book {
        let source = try await load(installed)
        let id = UUID()
        let folder = folder(of: Book(id: id, title: "", fileName: "", pageCount: 0))
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("chapters"), withIntermediateDirectories: true)
        var novel = Novel(title: details.series.title, author: details.author, summary: details.summary, chapters: [])
        novel.merge(details.chapters)
        try novel.save(to: folder)
        if let cover = details.series.cover,
           let (data, _) = try? await Network.session.data(for: source.imageRequest(cover)) {
            let original = folder.appendingPathComponent("cover-original")
            try? data.write(to: original)
            try? Thumbnail.make(from: original, to: folder.appendingPathComponent("cover.jpg"))
            try? FileManager.default.removeItem(at: original)
        }
        let book = Book(
            id: id, title: details.series.title, author: details.author, summary: details.summary,
            format: (details.isNovel ?? installed.info.novels) ? .novel : .series, fileName: installed.info.name,
            pageCount: novel.chapters.count, origin: origin, listed: listed
        )
        changeLibrary { $0.books.append(book) }
        return book
    }

    /// Asks the source for new chapters of a book. It gives the number of new chapters.
    @discardableResult
    func refresh(_ book: Book) async throws -> Int {
        guard let installed = installed(for: book), let origin = book.origin else { return 0 }
        let source = try await load(installed)
        let details = try await source.details(of: OnlineSeries(id: origin.series, title: book.title))
        var novel = try Novel.load(from: folder(of: book))
        let added = novel.merge(details.chapters)
        if added > 0 {
            try novel.save(to: folder(of: book))
            update(book.id) { $0.pageCount = novel.chapters.count; if added > 0 { $0.finished = false } }
        }
        return added
    }

    /// The file of a chapter of an online novel. It downloads the chapter the first time.
    func chapterFile(of book: Book, index: Int) async throws -> URL {
        let folder = folder(of: book)
        let novel = try Novel.load(from: folder)
        let chapter = novel.chapters[index]
        let file = folder.appendingPathComponent(chapter.path)
        if FileManager.default.fileExists(atPath: file.path) { return file }
        guard let remote = chapter.remote, let origin = book.origin else { throw ChapterFault.missing }
        guard let installed = installed(for: book) else { throw ChapterFault.sourceGone }
        let source = try await load(installed)
        let content = try await source.content(
            of: OnlineChapter(id: remote, title: chapter.title ?? ""), in: OnlineSeries(id: origin.series, title: book.title)
        )
        guard case let .html(html) = content else { throw ChapterFault.notText }
        let heading = chapter.title.map { "<h2>\(XHTML.escape($0))</h2>\n" } ?? ""
        let page = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>\(XHTML.escape(chapter.title ?? ""))</title></head><body>\n\(heading)\(html)\n</body></html>"
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(page.utf8).write(to: file, options: .atomic)
        return file
    }
}

// MARK: Search in all sources

extension AppModel {
    /// Searches some sources at the same time. `found` gets the first results of each source when it answers.
    func search(_ query: String, in sources: [InstalledSource], limit: Int = 12, found: @MainActor (String, [OnlineSeries]) -> Void) async {
        await withTaskGroup(of: (String, [OnlineSeries]).self) { group in
            func ask(_ installed: InstalledSource) -> @MainActor @Sendable () async -> (String, [OnlineSeries]) {
                {
                    guard let source = try? await self.load(installed),
                          let page = try? await source.search(query, page: 1)
                    else { return (installed.id, []) }
                    return (installed.id, Array(page.items.prefix(limit)))
                }
            }
            for (index, installed) in sources.enumerated() {
                // Six sources answer at the same time.
                if index >= 6, let (id, items) = await group.next() {
                    if Task.isCancelled { group.cancelAll(); return }
                    found(id, items)
                }
                group.addTask(operation: ask(installed))
            }
            for await (id, items) in group {
                if Task.isCancelled { group.cancelAll(); return }
                found(id, items)
            }
        }
    }

    /// The results of each source, in one list for each source.
    func search(_ query: String, in sources: [InstalledSource], limit: Int) async -> [[SearchHit]] {
        var all: [[SearchHit]] = []
        await search(query, in: sources, limit: limit) { id, items in
            all.append(items.map { SearchHit(source: id, series: $0) })
        }
        return all
    }
}
