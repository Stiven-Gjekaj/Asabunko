import Foundation

/// The chapters of a novel or of an online series in the folder of its book. Each importer of text writes it.
public struct Novel: Codable, Sendable, Equatable {
    public static let fileName = "novel.json"

    public struct Chapter: Codable, Sendable, Equatable {
        /// The title from the table of contents, or nil when the book does not give one.
        public var title: String?
        /// The path of the XHTML or HTML file, from the folder of the book.
        public var path: String
        /// The ID of the chapter in its online source. Its file comes when the user opens it.
        public var remote: String?

        public init(title: String?, path: String, remote: String? = nil) {
            self.title = title
            self.path = path
            self.remote = remote
        }
    }

    public var title: String
    public var author: String?
    public var summary: String?
    public var language: String?
    /// True when the pages go from the right to the left, as in a Japanese novel.
    public var rightToLeft: Bool
    public var chapters: [Chapter]

    public init(title: String, author: String? = nil, summary: String? = nil, language: String? = nil, rightToLeft: Bool = false, chapters: [Chapter]) {
        self.title = title
        self.author = author
        self.summary = summary
        self.language = language
        self.rightToLeft = rightToLeft
        self.chapters = chapters
    }

    public static func load(from folder: URL) throws -> Novel {
        try JSONDecoder().decode(Novel.self, from: Data(contentsOf: folder.appendingPathComponent(fileName)))
    }

    public func save(to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
    }
}

/// Writes text as simple XHTML, so that each importer of text gives the same kind of chapter.
public enum XHTML {
    public static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(ch)
            }
        }
        return out
    }

    public static func document(title: String?, body: String, language: String? = nil) -> String {
        let lang = language.map { " xml:lang=\"\(escape($0))\" lang=\"\(escape($0))\"" } ?? ""
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml"\(lang)>
        <head><meta charset="UTF-8"/><title>\(escape(title ?? ""))</title></head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    /// The paragraphs of plain text. A blank line ends a paragraph. With no blank line, each line is a paragraph.
    public static func paragraphs(_ text: String) -> String {
        let normal = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks: [String]
        if normal.contains("\n\n") {
            blocks = normal.components(separatedBy: "\n\n").map { $0.replacingOccurrences(of: "\n", with: " ") }
        } else {
            blocks = normal.components(separatedBy: "\n")
        }
        return blocks
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { "<p>\(escape($0))</p>" }
            .joined(separator: "\n")
    }
}

/// Reads text in the encoding that it has.
public enum TextDecoding {
    public static func decode(_ data: Data) -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(decoding: data.dropFirst(3), as: UTF8.self) }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            if let text = String(data: data, encoding: .utf16) { return text }
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        // Many old web novels are in Shift JIS or GB18030. GB18030 reads almost any bytes,
        // so Shift JIS comes first when it gives kana. GB text in Shift JIS gives half-width kana.
        if let text = String(data: data, encoding: .shiftJIS) {
            let scalars = text.unicodeScalars
            let kana = scalars.filter { (0x3040...0x30FF).contains($0.value) }.count
            let halfWidth = scalars.filter { (0xFF61...0xFF9F).contains($0.value) }.count
            if kana > 0 && halfWidth * 20 < scalars.count { return text }
        }
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        // Text with no byte above 0x7F is UTF-8 already, so only text with such bytes is here.
        // A western text in Windows-1252 has few of them, and GB18030 makes pairs of them.
        let high = data.filter { $0 >= 0x80 }.count
        if high * 10 > data.count, let text = String(data: data, encoding: gb) { return text }
        return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }
}

extension Novel {
    /// Adds the chapters of the source that the novel does not have yet, in the order of the source.
    /// A chapter that the source removed stays, so that its file and the place in it do not go.
    /// - Returns: the number of new chapters.
    @discardableResult
    public mutating func merge(_ online: [OnlineChapter], fileExtension: String = "html") -> Int {
        let known = Set(chapters.compactMap(\.remote))
        var added = 0
        for chapter in online where !known.contains(chapter.id) {
            let name = String(format: "chapters/%05d.%@", chapters.count + 1, fileExtension)
            chapters.append(Chapter(title: chapter.title, path: name, remote: chapter.id))
            added += 1
        }
        return added
    }
}
