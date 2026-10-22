import Foundation

/// Reads an EPUB 2 or EPUB 3 into the folder of a book.
/// The importer copies every file of the EPUB into content/, and writes novel.json with the
/// chapters in the order of the spine and their titles from the table of contents.
public enum EPUBImporter {
    public enum Failure: Error, Equatable {
        case noPackage
        case noChapters
        /// The EPUB has DRM, so the text cannot be read.
        case encrypted
    }

    public static func importBook(from url: URL, into folder: URL) throws -> Novel {
        let manager = FileManager.default
        let content = folder.appendingPathComponent("content", isDirectory: true)
        try manager.createDirectory(at: content, withIntermediateDirectories: true)
        do {
            try ArchiveReader.forEachFile(in: url) { entry, read in
                guard let path = safePath(entry.path) else { return }
                let file = content.appendingPathComponent(path)
                try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try read().write(to: file)
            }
            let (novel, cover) = try readPackage(in: content, fallbackTitle: ComicImporter.title(fromFileName: url.lastPathComponent))
            if let cover {
                try? Thumbnail.make(from: content.appendingPathComponent(cover), to: folder.appendingPathComponent("cover.jpg"))
            }
            try novel.save(to: folder)
            return novel
        } catch {
            try? manager.removeItem(at: folder)
            throw error
        }
    }

    /// A path in the archive that stays in the folder, or nil.
    static func safePath(_ path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard !parts.isEmpty, !path.hasPrefix("/"), !parts.contains(".."), !parts.contains("") else { return nil }
        return parts.joined(separator: "/")
    }

    /// The novel, and the path of its cover image from content/.
    static func readPackage(in content: URL, fallbackTitle: String) throws -> (Novel, String?) {
        if FileManager.default.fileExists(atPath: content.appendingPathComponent("META-INF/encryption.xml").path),
           let encryption = try? Data(contentsOf: content.appendingPathComponent("META-INF/encryption.xml")),
           let root = XMLElement.parse(encryption),
           // Fonts can be obfuscated with no DRM. Only an encrypted chapter stops the import.
           root.descendants("CipherReference").contains(where: { ($0["URI"] ?? "").lowercased().contains("htm") }) {
            throw Failure.encrypted
        }
        guard let containerData = try? Data(contentsOf: content.appendingPathComponent("META-INF/container.xml")),
              let container = XMLElement.parse(containerData),
              let opfPath = container.descendants("rootfile").first?["full-path"],
              let opfData = try? Data(contentsOf: content.appendingPathComponent(opfPath)),
              let opf = XMLElement.parse(opfData)
        else { throw Failure.noPackage }

        let base = (opfPath as NSString).deletingLastPathComponent
        func resolve(_ href: String) -> String {
            let clean = (href.components(separatedBy: "#").first ?? href).removingPercentEncoding ?? href
            return normalize(base.isEmpty ? clean : base + "/" + clean)
        }

        var manifest: [String: (href: String, type: String, properties: String)] = [:]
        for item in opf.descendants("item") {
            guard let id = item["id"], let href = item["href"] else { continue }
            manifest[id] = (href, item["media-type"] ?? "", item["properties"] ?? "")
        }

        let metadata = opf.child("metadata")
        let title = metadata?.child("title")?.allText.nonEmpty ?? fallbackTitle
        let author = metadata?.children("creator").map(\.allText).filter { !$0.isEmpty }.joined(separator: ", ").nonEmpty
        let summary = metadata?.child("description")?.allText.nonEmpty.map(stripTags)
        let language = metadata?.child("language")?.allText.nonEmpty

        // The titles of the table of contents, by the path of their file.
        var titles: [String: String] = [:]
        if let nav = manifest.values.first(where: { $0.properties.split(separator: " ").contains("nav") }),
           let data = try? Data(contentsOf: content.appendingPathComponent(resolve(nav.href))),
           let root = XMLElement.parse(data) {
            let navBase = (resolve(nav.href) as NSString).deletingLastPathComponent
            let tocs = root.descendants("nav").filter { ($0["epub:type"] ?? $0["type"] ?? "").contains("toc") }
            for link in (tocs.first ?? root).descendants("a") {
                guard let href = link["href"], let text = link.allText.nonEmpty else { continue }
                let path = normalize(navBase.isEmpty ? href.components(separatedBy: "#")[0] : navBase + "/" + href.components(separatedBy: "#")[0])
                if titles[path.removingPercentEncoding ?? path] == nil { titles[path.removingPercentEncoding ?? path] = text }
            }
        }
        let spine = opf.child("spine")
        if titles.isEmpty, let ncxID = spine?["toc"], let ncx = manifest[ncxID],
           let data = try? Data(contentsOf: content.appendingPathComponent(resolve(ncx.href))),
           let root = XMLElement.parse(data) {
            let ncxBase = (resolve(ncx.href) as NSString).deletingLastPathComponent
            for point in root.descendants("navPoint") {
                guard let src = point.child("content")?["src"], let text = point.child("navLabel")?.allText.nonEmpty else { continue }
                let clean = (src.components(separatedBy: "#")[0]).removingPercentEncoding ?? src
                let path = normalize(ncxBase.isEmpty ? clean : ncxBase + "/" + clean)
                if titles[path] == nil { titles[path] = text }
            }
        }

        var chapters: [Novel.Chapter] = []
        for itemref in spine?.children("itemref") ?? [] {
            guard let id = itemref["idref"], let item = manifest[id], item.type.contains("html") else { continue }
            let path = resolve(item.href)
            chapters.append(Novel.Chapter(title: titles[path], path: "content/" + path))
        }
        guard !chapters.isEmpty else { throw Failure.noChapters }

        // The cover: EPUB 3 marks it, EPUB 2 names it in the metadata.
        let coverID = manifest.first(where: { $0.value.properties.split(separator: " ").contains("cover-image") })?.key
            ?? metadata?.children("meta").first(where: { $0["name"] == "cover" })?["content"]
        let coverHref = coverID.flatMap { manifest[$0] }.flatMap { $0.type.hasPrefix("image/") ? $0.href : nil }
            ?? manifest.values.filter { $0.type.hasPrefix("image/") && $0.href.lowercased().contains("cover") }.map(\.href).sorted().first
        let novel = Novel(
            title: title, author: author, summary: summary, language: language,
            rightToLeft: spine?["page-progression-direction"] == "rtl", chapters: chapters
        )
        return (novel, coverHref.map(resolve))
    }

    /// "OEBPS/text/../images/a.png" gives "OEBPS/images/a.png".
    static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { if !parts.isEmpty { parts.removeLast() }; continue }
            parts.append(part)
        }
        return parts.joined(separator: "/")
    }

    static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
