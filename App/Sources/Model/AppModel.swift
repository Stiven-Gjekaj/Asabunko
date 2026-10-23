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

    private let root: URL
    private var libraryFile: URL { root.appendingPathComponent("library.json") }
    private var booksFolder: URL { root.appendingPathComponent("Books", isDirectory: true) }

    init(root: URL = AppModel.defaultRoot) {
        self.root = root
        do {
            library = try LibraryStore.load(from: libraryFile)
        } catch LibraryError.newerForm {
            fault = "A newer version of Asabunko wrote this library. Update the app to open it."
        } catch {
            fault = "The library file cannot be read."
        }
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
        library.books.removeAll { $0.id == book.id }
        try? FileManager.default.removeItem(at: folder(of: book))
        save()
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
        library.sources = lines.map(\.link)
        save()
        return library.sources
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

    // MARK: Store

    private func save() {
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
