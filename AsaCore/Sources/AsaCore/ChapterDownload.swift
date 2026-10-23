import ImageIO
import Foundation

/// The pages of a chapter of an online series on the device, so that the chapter opens with no network.
/// The pages of a chapter are in a folder next to the file of its chapter: chapters/00001/0001.jpg.
public enum ChapterDownload {
    /// The folder of the pages of a chapter, from its path in novel.json.
    public static func folder(of chapter: Novel.Chapter, in book: URL) -> URL {
        book.appendingPathComponent((chapter.path as NSString).deletingPathExtension, isDirectory: true)
    }

    /// The pages of a chapter that downloaded, in their order. A chapter that did not finish has no pages.
    public static func pages(of chapter: Novel.Chapter, in book: URL) -> [URL] {
        let folder = folder(of: chapter, in: book)
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent(".complete").path) else { return [] }
        return ComicImporter.pages(in: folder)
    }

    public static func isDownloaded(_ chapter: Novel.Chapter, in book: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder(of: chapter, in: book).appendingPathComponent(".complete").path)
    }

    /// The name of a page: its number from 1, and the extension of its kind of image.
    public static func pageName(_ index: Int, mimeType: String?, url: URL) -> String {
        let ext: String
        switch mimeType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "image/png": ext = "png"
        case "image/webp": ext = "webp"
        case "image/gif": ext = "gif"
        case "image/avif": ext = "avif"
        case "image/heic": ext = "heic"
        case "image/jpeg", "image/jpg": ext = "jpg"
        default:
            let fromURL = url.pathExtension.lowercased()
            ext = ComicImporter.imageExtensions.contains(fromURL) ? fromURL : "jpg"
        }
        return String(format: "%04d.%@", index + 1, ext)
    }

    /// Downloads the pages into the folder of the chapter. The folder gets its mark of completion only
    /// when each page came, so a chapter that stops half way does not open as a downloaded chapter.
    public static func download(
        _ requests: [URLRequest], chapter: Novel.Chapter, in book: URL, fetcher: Fetcher,
        progress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) async throws {
        let manager = FileManager.default
        let folder = folder(of: chapter, in: book)
        let staging = folder.deletingLastPathComponent().appendingPathComponent(folder.lastPathComponent + ".part", isDirectory: true)
        try? manager.removeItem(at: staging)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for (index, request) in requests.enumerated() {
                try Task.checkCancellation()
                var data = Data(), mime: String?
                var attempt = 0
                while true {
                    do {
                        // A page that the source drew on the device is a file already.
                        if let url = request.url, url.isFileURL {
                            data = try Data(contentsOf: url)
                            mime = "image/png"
                            break
                        }
                        let (body, response) = try await fetcher(request)
                        // A site can answer 200 with a page of HTML, such as a check or a refusal of hotlinks.
                        guard (200..<300).contains(response.statusCode), isImage(body) else { throw URLError(.cannotDecodeContentData) }
                        data = body
                        mime = response.value(forHTTPHeaderField: "Content-Type")
                        break
                    } catch {
                        attempt += 1
                        if attempt >= 3 { throw error }
                        try await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
                    }
                }
                try data.write(to: staging.appendingPathComponent(pageName(index, mimeType: mime, url: request.url ?? book)))
                progress(index + 1, requests.count)
            }
            try Data().write(to: staging.appendingPathComponent(".complete"))
            try? manager.removeItem(at: folder)
            try manager.moveItem(at: staging, to: folder)
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
    }

    /// True when the bytes are an image that ImageIO can read.
    public static func isImage(_ data: Data) -> Bool {
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0 && CGImageSourceGetType(source) != nil
    }

    /// Removes the pages of a chapter.
    public static func remove(_ chapter: Novel.Chapter, in book: URL) {
        try? FileManager.default.removeItem(at: folder(of: chapter, in: book))
    }
}

/// The space that files take on the device.
public enum FolderSize {
    /// The bytes of the files in a folder and in its folders. A folder that does not exist takes 0 bytes.
    public static func bytes(of folder: URL) -> Int64 {
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey])
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            guard let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]), values.isRegularFile == true
            else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }
}
