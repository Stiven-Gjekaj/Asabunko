import Foundation

/// The result of the import of one book of any format.
public struct ImportedBook: Sendable, Equatable {
    public var format: BookFormat
    public var title: String
    public var author: String?
    public var summary: String?
    /// The number of pages of a comic or a PDF, or the number of chapters of a novel.
    public var pageCount: Int
    /// The mode that the book asks for, or nil.
    public var mode: ReadingMode?
}

/// Chooses the importer from the kind of the file.
public enum BookImporter {
    public static let novelExtensions: Set<String> = ["epub", "txt", "text", "fb2", "html", "htm", "xhtml"]

    public static var supportedExtensions: Set<String> {
        ComicImporter.archiveExtensions.union(novelExtensions)
    }

    public static func canImport(_ url: URL) -> Bool {
        url.hasDirectoryPath || supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Imports the file or the folder into `folder`, with its cover. On a fault, `folder` does not stay.
    public static func importBook(from url: URL, into folder: URL) throws -> ImportedBook {
        let ext = url.pathExtension.lowercased()
        do {
            switch ext {
            case "epub":
                return novel(try EPUBImporter.importBook(from: url, into: folder))
            case "txt", "text":
                return novel(try TextImporter.importText(from: url, into: folder))
            case "html", "htm", "xhtml":
                return novel(try TextImporter.importHTML(from: url, into: folder))
            case "fb2":
                return novel(try FB2Importer.importBook(from: url, into: folder))
            default:
                let comic = try ComicImporter.importComic(from: url, into: folder)
                if let first = ComicImporter.pages(in: folder).first {
                    try? Thumbnail.make(from: first, to: folder.appendingPathComponent("cover.jpg"))
                }
                return ImportedBook(format: .comic, title: comic.title, author: comic.info?.writer, summary: comic.info?.summary,
                                    pageCount: comic.pageCount, mode: comic.info?.readingMode)
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    private static func novel(_ novel: Novel) -> ImportedBook {
        ImportedBook(format: .novel, title: novel.title, author: novel.author, summary: novel.summary,
                     pageCount: novel.chapters.count, mode: nil)
    }
}
