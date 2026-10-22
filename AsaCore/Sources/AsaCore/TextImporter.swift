import Foundation

/// Reads a TXT or an HTML file into the folder of a book as a novel.
public enum TextImporter {
    /// A long text with no headings gets parts of about this many characters.
    static let partLength = 60_000

    public static func importText(from url: URL, into folder: URL) throws -> Novel {
        let text = TextDecoding.decode(try Data(contentsOf: url))
        let title = ComicImporter.title(fromFileName: url.lastPathComponent)
        return try write(chapters: split(text), title: title, into: folder)
    }

    public static func importHTML(from url: URL, into folder: URL) throws -> Novel {
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try Data(contentsOf: url)
        try data.write(to: folder.appendingPathComponent("chapter.html"))
        let html = TextDecoding.decode(data)
        let found = html.range(of: "<title[^>]*>[\\s\\S]*?</title>", options: [.regularExpression, .caseInsensitive])
            .map { String(html[$0]).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression) }?.nonEmpty
        let novel = Novel(title: found ?? ComicImporter.title(fromFileName: url.lastPathComponent),
                          chapters: [.init(title: nil, path: "chapter.html")])
        try novel.save(to: folder)
        return novel
    }

    /// The chapters of a text: a line such as "Chapter 12", "Prologue", or "第十二章" starts a chapter.
    /// With fewer than two headings, a long text gets parts at the ends of paragraphs.
    static func split(_ text: String) -> [(title: String?, text: String)] {
        let normal = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normal.components(separatedBy: "\n")
        let heading = try! NSRegularExpression(
            pattern: #"^\s*((chapter|chap\.|part|volume|book|prologue|epilogue|interlude|afterword|side story)\b[^\n]{0,80}|第[0-9０-９〇零一二三四五六七八九十百千两]+[章話话节節回卷部].{0,40})\s*$"#,
            options: [.caseInsensitive]
        )
        var chapters: [(title: String?, lines: [String])] = [(nil, [])]
        var headings = 0
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if line.count <= 90, heading.firstMatch(in: line, range: range) != nil {
                headings += 1
                chapters.append((line.trimmingCharacters(in: .whitespaces), []))
            } else {
                chapters[chapters.count - 1].lines.append(line)
            }
        }
        if headings >= 2 {
            var result = chapters.map { ($0.title, $0.lines.joined(separator: "\n")) }
            // The text before the first heading is a chapter only when it has text.
            if result.first?.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { result.removeFirst() }
            return result
        }
        guard normal.count > partLength else { return [(nil, normal)] }
        var parts: [(String?, String)] = []
        var current = ""
        for paragraph in normal.components(separatedBy: "\n") {
            current += paragraph + "\n"
            if current.count >= partLength {
                parts.append(("Part \(parts.count + 1)", current))
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(("Part \(parts.count + 1)", current)) }
        return parts
    }

    static func write(chapters: [(title: String?, text: String)], title: String, author: String? = nil, summary: String? = nil, language: String? = nil, into folder: URL) throws -> Novel {
        let manager = FileManager.default
        let dir = folder.appendingPathComponent("chapters", isDirectory: true)
        try manager.createDirectory(at: dir, withIntermediateDirectories: true)
        var list: [Novel.Chapter] = []
        for (index, chapter) in chapters.enumerated() {
            let name = String(format: "%04d.xhtml", index + 1)
            let heading = chapter.title.map { "<h2>\(XHTML.escape($0))</h2>\n" } ?? ""
            let page = XHTML.document(title: chapter.title, body: heading + XHTML.paragraphs(chapter.text), language: language)
            try Data(page.utf8).write(to: dir.appendingPathComponent(name))
            list.append(.init(title: chapter.title, path: "chapters/" + name))
        }
        let novel = Novel(title: title, author: author, summary: summary, language: language, chapters: list)
        try novel.save(to: folder)
        return novel
    }
}

/// Reads a FictionBook 2 file, the common format of Russian e-books.
public enum FB2Importer {
    public static func importBook(from url: URL, into folder: URL) throws -> Novel {
        guard let root = XMLElement.parse(try Data(contentsOf: url)) else { throw EPUBImporter.Failure.noPackage }
        let manager = FileManager.default
        try manager.createDirectory(at: folder.appendingPathComponent("chapters/images"), withIntermediateDirectories: true)

        // The images are in base64, in <binary> elements at the end of the file.
        var images: [String: String] = [:]
        for (index, binary) in root.children("binary").enumerated() {
            guard let id = binary["id"], let data = Data(base64Encoded: binary.text, options: .ignoreUnknownCharacters) else { continue }
            let ext = (binary["content-type"] ?? "image/jpeg").contains("png") ? "png" : "jpg"
            let name = "images/\(index).\(ext)"
            try data.write(to: folder.appendingPathComponent("chapters/" + name))
            images[id] = name
        }

        let info = root.child("description")?.child("title-info")
        let title = info?.child("book-title")?.allText.nonEmpty ?? ComicImporter.title(fromFileName: url.lastPathComponent)
        let author = info?.children("author").map { author in
            ["first-name", "middle-name", "last-name"].compactMap { author.child($0)?.allText.nonEmpty }.joined(separator: " ")
        }.filter { !$0.isEmpty }.joined(separator: ", ").nonEmpty
        let summary = info?.child("annotation")?.allText.nonEmpty
        let language = info?.child("lang")?.allText.nonEmpty

        func href(_ element: XMLElement) -> String? {
            let link = element["href"] ?? element["l:href"] ?? element["xlink:href"]
            return link.map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }.flatMap { images[$0] }
        }

        func render(_ element: XMLElement) -> String {
            switch element.name {
            case "p": return "<p>\(XHTML.escape(element.allText))</p>"
            case "subtitle": return "<h3>\(XHTML.escape(element.allText))</h3>"
            case "empty-line": return "<br/>"
            case "image": return href(element).map { "<p><img src=\"\($0)\" alt=\"\"/></p>" } ?? ""
            case "poem", "stanza", "cite", "epigraph":
                return "<blockquote>" + element.children.map(render).joined(separator: "\n") + "</blockquote>"
            case "v": return "<p>\(XHTML.escape(element.allText))</p>"
            case "title", "section": return ""
            default: return element.children.map(render).joined(separator: "\n")
            }
        }

        // Each section with text is a chapter. A section that only holds sections gives its title to the first of them.
        var chapters: [(title: String?, body: String)] = []
        func walk(_ section: XMLElement, inherited: String?) {
            let own = section.child("title")?.allText.nonEmpty
            let body = section.children.filter { $0.name != "section" }.map(render).joined(separator: "\n")
            let subsections = section.children("section")
            if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || subsections.isEmpty {
                let name = [inherited, own].compactMap { $0 }.joined(separator: ": ").nonEmpty
                chapters.append((name, (own.map { "<h2>\(XHTML.escape($0))</h2>\n" } ?? "") + body))
                for sub in subsections { walk(sub, inherited: nil) }
            } else {
                for (index, sub) in subsections.enumerated() { walk(sub, inherited: index == 0 ? [inherited, own].compactMap { $0 }.joined(separator: ": ").nonEmpty : nil) }
            }
        }
        for body in root.children("body") where body["name"] != "notes" {
            for section in body.children("section") { walk(section, inherited: nil) }
        }
        guard !chapters.isEmpty else { throw EPUBImporter.Failure.noChapters }

        var list: [Novel.Chapter] = []
        for (index, chapter) in chapters.enumerated() {
            let name = String(format: "%04d.xhtml", index + 1)
            try Data(XHTML.document(title: chapter.title, body: chapter.body, language: language).utf8)
                .write(to: folder.appendingPathComponent("chapters/" + name))
            list.append(.init(title: chapter.title, path: "chapters/" + name))
        }
        if let coverID = info?.child("coverpage")?.child("image").flatMap(href) {
            try? Thumbnail.make(from: folder.appendingPathComponent("chapters/" + coverID), to: folder.appendingPathComponent("cover.jpg"))
        }
        let novel = Novel(title: title, author: author, summary: summary, language: language, chapters: list)
        try novel.save(to: folder)
        return novel
    }
}
