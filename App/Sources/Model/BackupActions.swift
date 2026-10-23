import AsaCore
import SwiftUI
import UniformTypeIdentifiers

/// The JSON file of a backup, for the file exporter.
struct BackupFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension AppModel {
    /// A backup of the library, with the chapters of each online book.
    func backup() throws -> Data {
        var chapters: [UUID: Novel] = [:]
        for book in library.books where book.origin != nil {
            if let novel = novel(of: book) { chapters[book.id] = novel }
        }
        return try Backup(library: library, chapters: chapters, app: "Asabunko").encoded()
    }

    /// Puts the backup in the place of the library. The code of each installed source downloads again.
    /// It gives the titles of the books from files that are not on this device.
    /// The books to import again, and the sources that did not install, such as with no network.
    func restore(_ backup: Backup) async -> (skipped: [String], sources: [String]) {
        let manager = FileManager.default
        let plan = backup.plan { manager.fileExists(atPath: folder(of: $0).path) }
        for (id, novel) in plan.chapters {
            let folder = folder(of: id)
            try? manager.createDirectory(at: folder.appendingPathComponent("chapters"), withIntermediateDirectories: true)
            if !manager.fileExists(atPath: folder.appendingPathComponent(Novel.fileName).path) { try? novel.save(to: folder) }
        }
        // A restore is the way out of a library file that did not load.
        unlockLibrary()
        changeLibrary { $0 = plan.library }
        var failed: [String] = []
        for installed in plan.library.installed {
            guard let link = plan.library.sources.first(where: { $0.id == installed.list }), link.kind != .suwayomi else { continue }
            do { try await install(installed.info, from: link) } catch { failed.append(installed.info.name) }
        }
        return (plan.skipped, failed)
    }

    /// Asks the source of each online book for new chapters. It gives the number of new chapters.
    /// Four books ask their sources at the same time, so a large library does not take minutes.
    /// With `readListOnly`, only the books of the read list ask, as in a check in the background.
    func refreshAll(readListOnly: Bool = false) async -> (added: Int, failed: Int, found: [(book: Book, added: Int)]) {
        var added = 0, failed = 0
        var found: [(book: Book, added: Int)] = []
        let books = library.books.filter { $0.origin != nil && (!readListOnly || $0.listed) }
        for start in stride(from: 0, to: books.count, by: 4) {
            await withTaskGroup(of: (Book, Int?).self) { group in
                for book in books[start..<min(start + 4, books.count)] {
                    group.addTask { (book, await self.refreshCounted(book)) }
                }
                for await (book, result) in group {
                    guard let result else { failed += 1; continue }
                    added += result
                    if result > 0 { found.append((book, result)) }
                }
            }
        }
        return (added, failed, found)
    }

    /// The number of new chapters of a book, or nil when its source did not answer.
    private func refreshCounted(_ book: Book) async -> Int? {
        do { return try await refresh(book) } catch { return nil }
    }

    /// The check of iOS in the background: the books of the read list ask for new chapters, and the user gets
    /// a notification for each book with new chapters. Then the app asks for the next check.
    func backgroundCheck() async {
        let result = await refreshAll(readListOnly: true)
        flush()
        await ChapterChecks.notify(result.found)
        ChapterChecks.schedule()
    }

    /// False when the user allows downloads only on Wi-Fi and the device is on another network.
    var mayDownloadNow: Bool {
        !UserDefaults.standard.bool(forKey: ChapterChecks.wifiKey) || NetworkKind.shared.isWiFi
    }
}
