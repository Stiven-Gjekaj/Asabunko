import AsaCore
import Foundation

/// The fetcher of the JavaScript and WebAssembly sources: the session of the app.
let appFetcher: Fetcher = { request in
    var request = request
    if request.value(forHTTPHeaderField: "User-Agent") == nil { request.setValue(Network.userAgent, forHTTPHeaderField: "User-Agent") }
    let (data, response) = try await Network.session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    return (data, http)
}

/// The sources that the app has loaded in this session, by the ID of their installation.
@MainActor
final class LoadedSources {
    static let shared = LoadedSources()
    private var sources: [String: OnlineSource] = [:]

    func get(_ id: String) -> OnlineSource? { sources[id] }
    func set(_ id: String, _ source: OnlineSource) { sources[id] = source }
    func remove(_ id: String) { sources[id] = nil }
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
        LoadedSources.shared.remove(installed.id)
        changeLibrary { $0.installed.removeAll { $0.id == installed.id } }
    }

    func kind(of installed: InstalledSource) -> SourceKind? {
        library.sources.first { $0.id == installed.list }?.kind
    }

    /// The source, loaded one time in each session.
    func load(_ installed: InstalledSource) async throws -> OnlineSource {
        if let source = LoadedSources.shared.get(installed.id) { return source }
        let source: OnlineSource
        switch kind(of: installed) {
        case .lnreader:
            let code = try Data(contentsOf: codeFile(of: installed))
            source = try await LNReaderPlugin(info: installed.info, code: String(decoding: code, as: UTF8.self), fetcher: appFetcher)
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
        LoadedSources.shared.set(installed.id, source)
        return source
    }

    /// The source of a book, when the book comes from an installed source.
    func installed(for book: Book) -> InstalledSource? {
        guard let origin = book.origin else { return nil }
        return library.installed.first { $0.list == origin.list && $0.info.id == origin.source }
    }

    // MARK: Online books

    /// Adds a series or a novel of a source to the library, with its chapters and its cover.
    @discardableResult
    func add(_ details: OnlineDetails, from installed: InstalledSource) async throws -> Book {
        let origin = BookOrigin(list: installed.list, source: installed.info.id, series: details.series.id)
        if let book = library.book(from: origin) { return book }
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
            format: installed.info.novels ? .novel : .series, fileName: installed.info.name,
            pageCount: novel.chapters.count, origin: origin
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
        guard let remote = chapter.remote, let installed = installed(for: book), let origin = book.origin else { return file }
        let source = try await load(installed)
        let content = try await source.content(
            of: OnlineChapter(id: remote, title: chapter.title ?? ""), in: OnlineSeries(id: origin.series, title: book.title)
        )
        guard case let .html(html) = content else { return file }
        let heading = chapter.title.map { "<h2>\(XHTML.escape($0))</h2>\n" } ?? ""
        let page = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>\(XHTML.escape(chapter.title ?? ""))</title></head><body>\n\(heading)\(html)\n</body></html>"
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(page.utf8).write(to: file, options: .atomic)
        return file
    }
}
