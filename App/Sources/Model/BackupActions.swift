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
        let plan = backup.plan { manager.fileExists(atPath: folder(of: Book(id: $0, title: "", fileName: "", pageCount: 0)).path) }
        for (id, novel) in plan.chapters {
            let folder = folder(of: Book(id: id, title: "", fileName: "", pageCount: 0))
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
    func refreshAll() async -> (added: Int, failed: Int) {
        var added = 0, failed = 0
        for book in library.books where book.origin != nil {
            do { added += try await refresh(book) } catch { failed += 1 }
        }
        return (added, failed)
    }
}
