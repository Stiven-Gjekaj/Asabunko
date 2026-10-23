import CArchive
import Foundation

/// Makes a file of a book in the library, to share it: a CBZ of the pages of a comic, the PDF of a PDF,
/// or the EPUB of a novel that came from an EPUB. Other books have no file to share.
public enum BookExport {
    public static func canShare(_ format: BookFormat, folder: URL) -> Bool {
        switch format {
        case .comic: true
        case .pdf: FileManager.default.fileExists(atPath: folder.appendingPathComponent(PDFImporter.fileName).path)
        case .novel: FileManager.default.fileExists(atPath: folder.appendingPathComponent("content/META-INF/container.xml").path)
        case .series: false
        }
    }

    /// Writes the file into `directory` with the title as its name, and gives its URL.
    public static func file(of format: BookFormat, title: String, folder: URL, into directory: URL) throws -> URL? {
        guard canShare(format, folder: folder) else { return nil }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let base = name.isEmpty ? "Book" : name
        switch format {
        case .comic:
            let target = directory.appendingPathComponent(base + ".cbz")
            try ZipWriter.write(try ComicImporter.pages(in: folder).map { ($0.lastPathComponent, try Data(contentsOf: $0)) }, to: target)
            return target
        case .pdf:
            let target = directory.appendingPathComponent(base + ".pdf")
            try? manager.removeItem(at: target)
            try manager.copyItem(at: folder.appendingPathComponent(PDFImporter.fileName), to: target)
            return target
        case .novel:
            // An EPUB starts with its mimetype file.
            let content = folder.appendingPathComponent("content", isDirectory: true)
            var files: [(String, Data)] = [("mimetype", Data("application/epub+zip".utf8))]
            let prefix = content.standardizedFileURL.path + "/"
            for case let url as URL in manager.enumerator(at: content, includingPropertiesForKeys: [.isRegularFileKey]) ?? FileManager.DirectoryEnumerator() {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let path = String(url.standardizedFileURL.path.dropFirst(prefix.count))
                if path != "mimetype" { files.append((path, try Data(contentsOf: url))) }
            }
            let target = directory.appendingPathComponent(base + ".epub")
            try ZipWriter.write(files, to: target)
            return target
        case .series:
            return nil
        }
    }
}

/// Writes a ZIP archive with no compression, with libarchive. The pages of a comic and the files of an EPUB
/// are compressed already, so a stored archive is almost as small, and it is fast. The mimetype of an EPUB
/// must be stored too.
public enum ZipWriter {
    public enum Failure: Error { case cannotWrite }

    public static func write(_ files: [(name: String, data: Data)], to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        guard let archive = archive_write_new() else { throw Failure.cannotWrite }
        defer { archive_write_free(archive) }
        archive_write_set_format_zip(archive)
        archive_write_set_options(archive, "zip:compression=store")
        guard archive_write_open_filename(archive, url.path) == ARCHIVE_OK else { throw Failure.cannotWrite }
        for (name, data) in files {
            guard let entry = archive_entry_new() else { throw Failure.cannotWrite }
            defer { archive_entry_free(entry) }
            archive_entry_set_pathname_utf8(entry, name)
            archive_entry_set_filetype(entry, UInt32(AE_IFREG))
            archive_entry_set_perm(entry, 0o644)
            archive_entry_set_size(entry, Int64(data.count))
            guard archive_write_header(archive, entry) == ARCHIVE_OK else { throw Failure.cannotWrite }
            let written = data.withUnsafeBytes { archive_write_data(archive, $0.baseAddress, data.count) }
            guard written == data.count else { throw Failure.cannotWrite }
        }
        guard archive_write_close(archive) == ARCHIVE_OK else { throw Failure.cannotWrite }
    }
}
