import AsaCore
import Foundation
import Observation

/// The state of the app: the library and the files of each book.
@MainActor
@Observable
final class AppModel {
    private(set) var library = Library()
    /// The fault of the last load or import, for an alert.
    var fault: String?
    /// The files that wait for import, and the number that the app imported.
    private(set) var importing: (done: Int, total: Int)?
    /// The downloads of the chapters of online series.
    let downloads = Downloads()
    /// The popular and the latest titles of the installed sources.
    let discover = DiscoverFeed()
    /// The install of the sources of new lines: the sources that installed, of all of them.
    private(set) var sourceSetup: (done: Int, total: Int)?

    private let root: URL
    private var libraryFile: URL { root.appendingPathComponent("library.json") }
    private var booksFolder: URL { root.appendingPathComponent("Books", isDirectory: true) }

    /// True when the library file did not load. Then no save writes over it, until the user
    /// restores a backup or starts a new library.
    private(set) var libraryLocked = false
    private var saveTask: Task<Void, Never>?
    /// The adds of online books that run now, so that two taps add one book.
    var adding: [BookOrigin: Task<Book, Error>] = [:]

    init(root: URL = AppModel.defaultRoot) {
        self.root = root
        do {
            library = try LibraryStore.load(from: libraryFile)
        } catch LibraryError.newerForm {
            libraryLocked = true
            fault = "A newer version of Asabunko wrote this library. Update the app to open it. Asabunko does not change the file."
        } catch {
            libraryLocked = true
            let copy = try? LibraryStore.keepBroken(libraryFile)
            fault = "The library file cannot be read. Asabunko does not change it" + (copy.map { ", and keeps a copy as \($0.lastPathComponent)" } ?? "")
                + ". Restore a backup, or start a new library in Settings."
        }
    }

    func unlockLibrary() { libraryLocked = false }

    /// Starts an empty library in place of a file that did not load. The copy of the old file stays.
    func startNewLibrary() {
        libraryLocked = false
        library = Library()
        save()
    }

    /// The folder of the library. A UI test gives an empty folder in ASABUNKO_ROOT.
    static var defaultRoot: URL {
        if let path = ProcessInfo.processInfo.environment["ASABUNKO_ROOT"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL.applicationSupportDirectory.appendingPathComponent("Asabunko", isDirectory: true)
    }

    // MARK: Books

    func folder(of book: Book) -> URL {
        booksFolder.appendingPathComponent(book.id.uuidString, isDirectory: true)
    }

    func cover(of book: Book) -> URL {
        folder(of: book).appendingPathComponent("cover.jpg")
    }

    func pages(of book: Book) -> [URL] {
        ComicImporter.pages(in: folder(of: book))
    }

    func novel(of book: Book) -> Novel? {
        try? Novel.load(from: folder(of: book))
    }

    func book(_ id: Book.ID) -> Book? {
        library.books.first { $0.id == id }
    }

    func mode(of book: Book) -> ReadingMode {
        library.mode(of: book)
    }

    func update(_ id: Book.ID, _ change: (inout Book) -> Void) {
        guard let index = library.books.firstIndex(where: { $0.id == id }) else { return }
        change(&library.books[index])
        save()
    }

    func setDefaultMode(_ mode: ReadingMode) {
        library.defaultMode = mode
        save()
    }

    func delete(_ book: Book) {
        downloads.cancel(book.id)
        library.books.removeAll { $0.id == book.id }
        try? FileManager.default.removeItem(at: folder(of: book))
        save()
    }

    /// Removes the folder of a book that is not in the library.
    func removeFolder(of id: Book.ID) {
        guard book(id) == nil else { return }
        try? FileManager.default.removeItem(at: folder(of: Book(id: id, title: "", fileName: "", pageCount: 0)))
    }

    // MARK: Import

    /// Imports each file or folder. A fault stops only its own file.
    func importItems(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        importing = (0, urls.count)
        var failed: [String] = []
        for (index, url) in urls.enumerated() {
            let id = UUID()
            let folder = booksFolder.appendingPathComponent(id.uuidString, isDirectory: true)
            let result = await Task.detached(priority: .userInitiated) { () -> Result<ImportedBook, Error> in
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    return .success(try BookImporter.importBook(from: url, into: folder))
                } catch {
                    return .failure(error)
                }
            }.value
            switch result {
            case let .success(imported):
                library.books.append(Book(
                    id: id, title: imported.title, author: imported.author, summary: imported.summary,
                    format: imported.format, fileName: url.lastPathComponent, pageCount: imported.pageCount, mode: imported.mode
                ))
                save()
            case let .failure(error):
                failed.append("\(url.lastPathComponent): \(Self.describe(error))")
            }
            importing = (index + 1, urls.count)
        }
        importing = nil
        if !failed.isEmpty { fault = "Some files were not imported.\n\n" + failed.joined(separator: "\n") }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case ImportError.noPages: "The file has no images."
        case let ImportError.unsupported(ext): "Asabunko cannot read .\(ext) files yet."
        case ArchiveError.cannotOpen, ArchiveError.cannotRead: "The archive is damaged or locked with a password."
        case EPUBImporter.Failure.encrypted: "The book has DRM. Asabunko reads only books with no DRM."
        case EPUBImporter.Failure.noPackage: "The book is damaged. It has no package file."
        case EPUBImporter.Failure.noChapters: "The book has no chapters."
        case MOBIImporter.Failure.encrypted: "The Kindle book has DRM. Asabunko reads only books with no DRM."
        case MOBIImporter.Failure.unsupportedCompression: "The Kindle book uses the compression of the Kindle store, which Asabunko cannot read."
        case MOBIImporter.Failure.notMOBI: "The file is not a MOBI or AZW3 book."
        case MOBIImporter.Failure.noText: "The Kindle book has no text."
        case PDFImporter.Failure.locked: "The PDF needs a password. Remove the password, then import it again."
        case PDFImporter.Failure.notPDF: "The file is not a PDF."
        case PDFImporter.Failure.noPages: "The PDF has no pages."
        default: error.localizedDescription
        }
    }

    // MARK: Sources

    /// Replaces the source list with the text of the paste box. A password goes to the Keychain.
    /// A line with a user name and no password keeps the password that the Keychain has.
    @discardableResult
    func saveSources(_ text: String) -> [SourceLink] {
        let lines = SourceList.parse(text, existing: library.sources)
        let kept = Set(lines.map(\.link.id))
        for old in library.sources where !kept.contains(old.id) { Keychain.setPassword(nil, for: old.id) }
        for line in lines where line.password != nil { Keychain.setPassword(line.password, for: line.link.id) }
        let added = lines.map(\.link).filter { link in !library.sources.contains { $0.id == link.id } }
        library.sources = lines.map(\.link)
        // The sources of a line that the user removed go too.
        for installed in library.installed where !kept.contains(installed.list) { uninstall(installed) }
        save()
        if !added.isEmpty { Task { await setUp(added) } }
        return library.sources
    }

    /// Finds the kind of each new line and installs the sources of each list, with no question.
    /// Only the sources in the languages of the device go in. The user removes a source in Settings.
    func setUp(_ links: [SourceLink]) async {
        var failed: [String] = []
        for var link in links {
            if link.kind == nil {
                guard let kind = await detect(link) else {
                    failed.append(link.shortAddress)
                    continue
                }
                learn(link.id, kind: kind, name: nil)
                link.kind = kind
            }
            guard link.kind != .opds else { continue }
            let infos: [SourceInfo]
            do {
                infos = try await sources(in: link)
            } catch {
                failed.append(link.name ?? link.shortAddress)
                continue
            }
            let adult = UserDefaults.standard.bool(forKey: "browse.adult")
            let picked = SourceLanguages.pick(infos, preferred: Locale.preferredLanguages, adult: adult).filter { !isInstalled($0, from: link) }
            await installAll(picked, from: link)
        }
        // A book of a line that the user removed and added again finds its source.
        changeLibrary { $0.relinkOrphans() }
        if !failed.isEmpty { fault = "Asabunko could not read " + failed.joined(separator: ", ") + "." }
    }

    /// Installs some sources at the same time, and counts them.
    private func installAll(_ infos: [SourceInfo], from link: SourceLink) async {
        guard !infos.isEmpty else { return }
        sourceSetup = (0, infos.count)
        defer { sourceSetup = nil }
        let total = infos.count
        // Four installs run at the same time.
        for start in stride(from: 0, to: total, by: 4) {
            let part = Array(infos[start..<min(start + 4, total)])
            await withTaskGroup(of: Void.self) { group in
                for info in part {
                    group.addTask { await self.installQuietly(info, from: link) }
                }
            }
            sourceSetup = (min(start + 4, total), total)
        }
    }

    /// Installs a source. A source that does not install stays out, and the others go on.
    private func installQuietly(_ info: SourceInfo, from link: SourceLink) async {
        do { try await install(info, from: link) } catch {}
    }

    /// The kind of a line from its content. A Paperback repository can be a folder with a versioning.json in it.
    private func detect(_ link: SourceLink) async -> SourceKind? {
        if let data = try? await Network.data(for: AppModel.request(link.url, source: link)), let kind = SourceKind.detect(data) { return kind }
        guard link.url.pathExtension.isEmpty,
              let data = try? await Network.data(for: AppModel.request(link.url.appendingPathComponent("versioning.json"), source: link)),
              SourceKind.detect(data) == .paperback
        else { return nil }
        return .paperback
    }

    /// Keeps the kind and the name that the app found when it read a source.
    func learn(_ id: SourceLink.ID, kind: SourceKind?, name: String?) {
        guard let index = library.sources.firstIndex(where: { $0.id == id }) else { return }
        if let kind { library.sources[index].kind = kind }
        if let name, !name.isEmpty { library.sources[index].name = name }
        save()
    }

    /// A request to a source, with its user name and its password when it has them.
    nonisolated static func request(_ url: URL, source: SourceLink?) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/atom+xml, application/opds+json, application/json;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")
        // The password goes only to the host of the source. A link to another host gets no password.
        if let source, let user = source.username, !user.isEmpty, url.host == source.url.host {
            let password = Keychain.password(for: source.id) ?? ""
            request.setValue("Basic " + Data("\(user):\(password)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Downloads a book from the network and imports it into the library.
    func download(_ request: URLRequest, title: String, fileExtension: String) async {
        do {
            let (temporary, response) = try await Network.session.download(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw Network.Failure.status(http.statusCode)
            }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let safe = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let file = folder.appendingPathComponent("\(safe.isEmpty ? "Book" : safe).\(fileExtension)")
            try FileManager.default.moveItem(at: temporary, to: file)
            await importItems([file])
        } catch {
            fault = "The book was not downloaded: \(error.localizedDescription)"
        }
    }

    /// Changes the library and saves it.
    func changeLibrary(_ change: (inout Library) -> Void) {
        change(&library)
        save()
    }

    // MARK: Store

    /// Writes the library a short time after the last change, off the main thread. A page turn changes
    /// the library, so many changes become one write.
    private func save() {
        guard !libraryLocked else { return }
        saveTask?.cancel()
        let snapshot = library
        let file = libraryFile
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .utility) { Result { try LibraryStore.save(snapshot, to: file) } }.value
            if case let .failure(error) = result { self?.fault = "The library was not saved: \(error.localizedDescription)" }
        }
    }

    /// Writes the library now, such as when the app goes to the background.
    func flush() {
        guard !libraryLocked, let task = saveTask else { return }
        task.cancel()
        saveTask = nil
        do {
            try LibraryStore.save(library, to: libraryFile)
        } catch {
            fault = "The library was not saved: \(error.localizedDescription)"
        }
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static let repository = "https://github.com/Stiven-Gjekaj/Asabunko"
    static let kofi = "https://ko-fi.com/stivengjekaj"
}
