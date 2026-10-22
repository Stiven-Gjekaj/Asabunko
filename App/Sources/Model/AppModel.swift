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
            let result = await Task.detached(priority: .userInitiated) { () -> Result<ImportedComic, Error> in
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let comic = try ComicImporter.importComic(from: url, into: folder)
                    if let first = ComicImporter.pages(in: folder).first {
                        try? Thumbnail.make(from: first, to: folder.appendingPathComponent("cover.jpg"))
                    }
                    return .success(comic)
                } catch {
                    return .failure(error)
                }
            }.value
            switch result {
            case let .success(comic):
                library.books.append(Book(
                    id: id, title: comic.title, author: comic.info?.writer, summary: comic.info?.summary,
                    fileName: url.lastPathComponent, pageCount: comic.pageCount, mode: comic.info?.readingMode
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
        default: error.localizedDescription
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
