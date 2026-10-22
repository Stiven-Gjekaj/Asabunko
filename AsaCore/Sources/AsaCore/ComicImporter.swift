import Foundation

/// The result of the import of one comic.
public struct ImportedComic: Sendable, Equatable {
    public let title: String
    public let pageCount: Int
    public let info: ComicInfo?
}

public enum ImportError: Error, Equatable {
    /// The file is not a kind that the app can read.
    case unsupported(String)
    /// The archive or the folder has no images.
    case noPages
}

/// Copies the pages of a comic into a folder of the library.
/// The pages get the names 0001.jpg, 0002.png, and so on, in the natural order
/// of their paths. A name in an archive can hold "..", so the app never uses it
/// as a path.
public enum ComicImporter {
    public static let archiveExtensions: Set<String> = ["cbz", "zip", "cbr", "rar", "cb7", "7z", "cbt", "tar"]
    public static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "avif", "heic", "heif", "bmp", "tif", "tiff", "jxl",
    ]

    public static func canImport(_ url: URL) -> Bool {
        url.hasDirectoryPath || archiveExtensions.contains(url.pathExtension.lowercased())
    }

    /// Imports an archive or a folder of images into `folder`, which must not exist.
    public static func importComic(from url: URL, into folder: URL) throws -> ImportedComic {
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? url.hasDirectoryPath
        guard isFolder || archiveExtensions.contains(url.pathExtension.lowercased()) else {
            throw ImportError.unsupported(url.pathExtension)
        }
        let manager = FileManager.default
        let staging = folder.appendingPathComponent(".staging", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            var staged: [(path: String, file: URL)] = []
            var info: ComicInfo?
            func stage(path: String, data: Data) throws {
                let file = staging.appendingPathComponent("\(staged.count)")
                try data.write(to: file)
                staged.append((path, file))
            }

            if isFolder {
                for (path, file) in imageFiles(in: url) {
                    try stage(path: path, data: Data(contentsOf: file))
                }
                let infoFile = url.appendingPathComponent("ComicInfo.xml")
                if let data = try? Data(contentsOf: infoFile) { info = ComicInfo.parse(data) }
            } else {
                try ArchiveReader.forEachFile(in: url) { entry, read in
                    if isComicInfo(entry.path) {
                        info = ComicInfo.parse(try read())
                    } else if isPage(entry.path) {
                        try stage(path: entry.path, data: read())
                    }
                }
            }

            guard !staged.isEmpty else { throw ImportError.noPages }
            let order = staged.sorted { NaturalOrder.areInIncreasingOrder($0.path, $1.path) }
            for (index, page) in order.enumerated() {
                let name = pageName(index, extension: (page.path as NSString).pathExtension)
                try manager.moveItem(at: page.file, to: folder.appendingPathComponent(name))
            }
            try manager.removeItem(at: staging)
            let title = info?.displayTitle ?? title(fromFileName: url.lastPathComponent)
            return ImportedComic(title: title, pageCount: order.count, info: info)
        } catch {
            try? manager.removeItem(at: folder)
            throw error
        }
    }

    /// The names of the pages in a book folder, in the order of reading.
    public static func pages(in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { isPage($0) && !$0.hasPrefix(".") && !$0.hasPrefix("cover.") }
            .sorted()
            .map { folder.appendingPathComponent($0) }
    }

    static func pageName(_ index: Int, extension ext: String) -> String {
        String(format: "%04d.%@", index + 1, ext.lowercased())
    }

    static func isPage(_ path: String) -> Bool {
        guard !isHidden(path) else { return false }
        return imageExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    static func isComicInfo(_ path: String) -> Bool {
        !isHidden(path) && (path as NSString).lastPathComponent.caseInsensitiveCompare("ComicInfo.xml") == .orderedSame
    }

    /// A file of macOS, such as __MACOSX/ or ._page.jpg, is not a page.
    /// A path with a ".." part is not a page either, because it points out of the archive.
    static func isHidden(_ path: String) -> Bool {
        path.split(separator: "/").contains { $0.hasPrefix(".") || $0 == "__MACOSX" }
    }

    /// "My_Comic_v01.cbz" gives "My Comic v01".
    public static func title(fromFileName name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        let spaced = base.replacingOccurrences(of: "_", with: " ")
        return spaced.nonEmpty ?? name
    }

    private static func imageFiles(in folder: URL) -> [(String, URL)] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        let root = folder.standardizedFileURL.path
        var files: [(String, URL)] = []
        for case let file as URL in enumerator {
            let full = file.standardizedFileURL.path
            let path = full.hasPrefix(root) ? String(full.dropFirst(root.count + 1)) : file.lastPathComponent
            if isPage(path) { files.append((path, file)) }
        }
        return files
    }
}
