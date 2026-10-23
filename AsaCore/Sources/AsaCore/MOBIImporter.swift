import Foundation

/// Reads a MOBI, AZW, or AZW3 book with no DRM into the folder of a book.
/// A MOBI 6 book is one HTML text with page breaks. A KF8 book, such as an AZW3, keeps its text
/// as skeletons and fragments, and the importer joins them again. The importer writes each part
/// as a chapter in text/, the images in images/, the styles in styles/, and novel.json.
public enum MOBIImporter {
    public enum Failure: Error, Equatable {
        case notMOBI
        /// The book has DRM, so the text cannot be read.
        case encrypted
        /// The book uses the HUFF/CDIC compression of the Kindle store.
        case unsupportedCompression(Int)
        case noText
    }

    public static func importBook(from url: URL, into folder: URL) throws -> Novel {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let book = try read(try Data(contentsOf: url), fallbackTitle: ComicImporter.title(fromFileName: url.lastPathComponent))
            let novel = try book.write(to: folder)
            return novel
        } catch {
            try? manager.removeItem(at: folder)
            throw error
        }
    }

    // MARK: The book in memory

    /// A book that the importer read, before it writes its files.
    struct Book {
        var title: String
        var author: String?
        var summary: String?
        var language: String?
        /// The HTML of each part, with links to images/ and styles/.
        var parts: [String]
        /// The image files, by their name in images/.
        var images: [(name: String, data: Data)]
        /// The style sheets, by their name in styles/.
        var styles: [(name: String, data: Data)]
        var cover: String?

        func write(to folder: URL) throws -> Novel {
            let manager = FileManager.default
            for (directory, files) in [("images", images), ("styles", styles)] where !files.isEmpty {
                let place = folder.appendingPathComponent(directory, isDirectory: true)
                try manager.createDirectory(at: place, withIntermediateDirectories: true)
                for file in files { try file.data.write(to: place.appendingPathComponent(file.name)) }
            }
            let text = folder.appendingPathComponent("text", isDirectory: true)
            try manager.createDirectory(at: text, withIntermediateDirectories: true)
            var chapters: [Novel.Chapter] = []
            for (index, part) in parts.enumerated() {
                let name = String(format: "text/%05d.html", index + 1)
                try Data(part.utf8).write(to: folder.appendingPathComponent(name))
                chapters.append(Novel.Chapter(title: MOBIImporter.heading(in: part), path: name))
            }
            let novel = Novel(title: title, author: author, summary: summary, language: language, chapters: chapters)
            try novel.save(to: folder)
            if let cover {
                try? Thumbnail.make(from: folder.appendingPathComponent("images").appendingPathComponent(cover), to: folder.appendingPathComponent("cover.jpg"))
            }
            return novel
        }
    }

    static func read(_ data: Data, fallbackTitle: String) throws -> Book {
        let db = try PalmDB(data)
        guard db.records.count > 1 else { throw Failure.notMOBI }
        let first = try Header(db.record(0))
        // A joint file has a MOBI 6 book and a KF8 book. The KF8 book is newer and better.
        if first.version >= 8 {
            return try kf8(db, header: first, start: 0, fallbackTitle: fallbackTitle)
        }
        if let boundary = first.exth.boundary, boundary > 0, boundary < db.records.count,
           let header = try? Header(db.record(boundary)), header.version >= 8,
           let book = try? kf8(db, header: header, start: boundary, fallbackTitle: fallbackTitle) {
            return book
        }
        return try mobi6(db, header: first, fallbackTitle: fallbackTitle)
    }

    // MARK: MOBI 6

    private static func mobi6(_ db: PalmDB, header: Header, fallbackTitle: String) throws -> Book {
        let raw = try text(db, header: header, start: 0)
        var html = decodeText(raw, encoding: header.encoding)
        let images = resources(db, header: header, start: 0)
        // <img recindex="00003"> points to the third image record.
        html = replace(#"recindex\s*=\s*["']?0*(\d+)["']?"#, in: html) { groups in
            guard let number = Int(groups[1]), let image = images.byNumber[number] else { return "" }
            return "src=\"../images/\(image)\""
        }
        // A filepos link points to a byte of the full text. The parts are files now, so the link goes.
        html = replace(#"filepos\s*=\s*["']?\d+["']?"#, in: html) { _ in "href=\"#\"" }
        let body = MOBIImporter.body(of: html)
        let pieces = replace(#"<mbp:pagebreak\s*/?>"#, in: body) { _ in "\u{1}" }.components(separatedBy: "\u{1}").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !strippedText($0).isEmpty || $0.contains("<img") }
        guard !pieces.isEmpty else { throw Failure.noText }
        let parts = pieces.map { piece in document(title: heading(in: "<body>" + piece), body: piece, styles: []) }
        return Book(
            title: header.exth.title ?? header.fullName ?? fallbackTitle, author: header.exth.author, summary: header.exth.summary,
            language: header.exth.language, parts: parts, images: images.files, styles: [], cover: images.cover
        )
    }

    // MARK: KF8

    private static func kf8(_ db: PalmDB, header: Header, start: Int, fallbackTitle: String) throws -> Book {
        let raw = try text(db, header: header, start: start)
        // The flows: the first is the text, the others are style sheets and images in SVG.
        var flows: [Data] = [raw]
        if let fdst = header.fdstIndex, let record = try? db.record(start + fdst), record.prefix(4) == Data("FDST".utf8) {
            let count = Int(record.u32(8))
            flows = (0..<count).compactMap { index in
                let from = Int(record.u32(12 + index * 8)), to = Int(record.u32(16 + index * 8))
                guard from <= to, to <= raw.count else { return nil }
                return raw.subdata(in: from..<to)
            }
            if flows.isEmpty { flows = [raw] }
        }
        var pieces: [Data] = [flows[0]]
        if let skelIndex = header.skeletonIndex, let fragIndex = header.fragmentIndex {
            let skeletons = try Index.read(db, at: start + skelIndex).map { entry -> Skeleton in
                let count = entry.tags[1]?.first ?? 0
                let place = entry.tags[6] ?? []
                return Skeleton(fragments: count, start: place.first ?? 0, length: place.count > 1 ? place[1] : 0)
            }
            let fragments = try Index.read(db, at: start + fragIndex).map { entry -> Fragment in
                let place = entry.tags[6] ?? []
                return Fragment(insert: Int(entry.name) ?? 0, start: place.first ?? 0, length: place.count > 1 ? place[1] : 0)
            }
            if !skeletons.isEmpty { pieces = assemble(flows[0], skeletons: skeletons, fragments: fragments) }
        }

        let images = resources(db, header: header, start: start)
        var styles: [(name: String, data: Data)] = []
        for (index, flow) in flows.enumerated().dropFirst() {
            let text = String(decoding: flow, as: UTF8.self)
            let kind = text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<svg") ? "svg" : "css"
            styles.append((String(format: "flow%04d.%@", index, kind), Data(links(text, images: images, styles: []).utf8)))
        }
        let styleNames = styles.map(\.name)
        var parts: [String] = []
        for piece in pieces {
            let html = links(decodeText(piece, encoding: header.encoding), images: images, styles: styleNames)
            guard !strippedText(MOBIImporter.body(of: html)).isEmpty || html.contains("<img") || html.contains("<svg") else { continue }
            parts.append(html)
        }
        guard !parts.isEmpty else { throw Failure.noText }
        return Book(
            title: header.exth.title ?? header.fullName ?? fallbackTitle, author: header.exth.author, summary: header.exth.summary,
            language: header.exth.language, parts: parts, images: images.files, styles: styles, cover: images.cover
        )
    }

    struct Skeleton: Equatable {
        var fragments: Int
        var start: Int
        var length: Int
    }

    struct Fragment: Equatable {
        /// The place in the full text where the fragment goes.
        var insert: Int
        var start: Int
        var length: Int
    }

    /// Puts each fragment into its skeleton, as the KF8 format needs. Each skeleton is one part of the book.
    static func assemble(_ text: Data, skeletons: [Skeleton], fragments: [Fragment]) -> [Data] {
        var parts: [Data] = []
        var next = 0
        for skeleton in skeletons {
            guard skeleton.start >= 0, skeleton.start + skeleton.length <= text.count else { continue }
            var base = skeleton.start + skeleton.length
            var part = text.subdata(in: skeleton.start..<base)
            for _ in 0..<skeleton.fragments where next < fragments.count {
                let fragment = fragments[next]
                next += 1
                guard base + fragment.length <= text.count else { continue }
                let piece = text.subdata(in: base..<(base + fragment.length))
                let at = min(max(fragment.insert - skeleton.start, 0), part.count)
                part.replaceSubrange(at..<at, with: piece)
                base += fragment.length
            }
            parts.append(part)
        }
        return parts
    }

    /// Changes the links of KF8 to the files of the folder: kindle:embed to images/, kindle:flow to styles/.
    static func links(_ html: String, images: Resources, styles: [String]) -> String {
        var html = replace(#"kindle:embed:([0-9A-Va-v]{4})(\?mime=[^"')\s]*)?"#, in: html) { groups in
            guard let number = Int(groups[1], radix: 32), let image = images.byNumber[number] else { return "" }
            return "../images/\(image)"
        }
        html = replace(#"kindle:flow:([0-9A-Va-v]{4})(\?mime=[^"')\s]*)?"#, in: html) { groups in
            guard let number = Int(groups[1], radix: 32), number >= 1, number <= styles.count else { return "" }
            return "../styles/\(styles[number - 1])"
        }
        // A link to a place in the book points to a byte of the full text. The parts are files now, so it goes.
        return replace(#"kindle:pos:fid:[0-9A-Va-v]+:off:[0-9A-Va-v]+"#, in: html) { _ in "#" }
    }

    // MARK: The text records

    /// The text of the book: the text records, with no trailing entries, and decompressed.
    static func text(_ db: PalmDB, header: Header, start: Int) throws -> Data {
        guard header.encryption == 0 else { throw Failure.encrypted }
        var text = Data()
        text.reserveCapacity(header.textLength)
        for index in 1...max(header.recordCount, 1) where start + index < db.records.count {
            var record = try db.record(start + index)
            record = record.prefix(record.count - trailingSize(record, flags: header.extraFlags))
            switch header.compression {
            case 1: text.append(record)
            case 2: text.append(palmDOC(record))
            default: throw Failure.unsupportedCompression(header.compression)
            }
        }
        if text.count > header.textLength && header.textLength > 0 { text = text.prefix(header.textLength) }
        guard !text.isEmpty else { throw Failure.noText }
        return Data(text)
    }

    /// The size of the extra bytes at the end of a text record, which the flags of the header tell.
    static func trailingSize(_ record: Data, flags: Int) -> Int {
        let bytes = [UInt8](record)
        var size = 0
        var rest = flags >> 1
        while rest != 0 {
            if rest & 1 != 0 {
                // The size of each entry is a number in its last bytes, read from the end.
                var value = 0, shift = 0, at = bytes.count - size
                while at > 0 {
                    let byte = Int(bytes[at - 1])
                    value |= (byte & 0x7F) << shift
                    shift += 7
                    at -= 1
                    if byte & 0x80 != 0 || shift >= 28 { break }
                }
                size += value
            }
            rest >>= 1
        }
        if flags & 1 != 0, bytes.count > size {
            size += Int(bytes[bytes.count - size - 1] & 0x3) + 1
        }
        return min(size, bytes.count)
    }

    /// The LZ77 compression of PalmDOC.
    static func palmDOC(_ data: Data) -> Data {
        let input = [UInt8](data)
        var out: [UInt8] = []
        out.reserveCapacity(input.count * 2)
        var i = 0
        while i < input.count {
            let c = input[i]
            i += 1
            switch c {
            case 0x01...0x08:
                let end = min(i + Int(c), input.count)
                out.append(contentsOf: input[i..<end])
                i = end
            case 0x80...0xBF:
                guard i < input.count else { break }
                let pair = (Int(c) << 8) | Int(input[i])
                i += 1
                let distance = (pair >> 3) & 0x7FF
                let length = (pair & 0x7) + 3
                guard distance > 0, distance <= out.count else { continue }
                for _ in 0..<length { out.append(out[out.count - distance]) }
            case 0xC0...0xFF:
                out.append(0x20)
                out.append(c ^ 0x80)
            default:
                out.append(c)
            }
        }
        return Data(out)
    }

    // MARK: The images

    struct Resources {
        /// The name of each image by its number, from 1.
        var byNumber: [Int: String] = [:]
        var files: [(name: String, data: Data)] = []
        var cover: String?
    }

    /// The images of the book, from the first image record to the end.
    static func resources(_ db: PalmDB, header: Header, start: Int) -> Resources {
        var result = Resources()
        guard let first = header.firstImage, first > 0 else { return result }
        var number = 1
        var index = start + first
        while index < db.records.count {
            defer { number += 1; index += 1 }
            guard let record = try? db.record(index), let kind = imageKind(record) else {
                // The book ends with records that are not images, such as FLIS and EOF.
                if let record = try? db.record(index), ["FLIS", "FCIS", "SRCS", "\u{e9}\u{8e}\r\n"].contains(String(decoding: record.prefix(4), as: UTF8.self)) { break }
                continue
            }
            let name = String(format: "%05d.%@", number, kind)
            result.byNumber[number] = name
            result.files.append((name, record))
        }
        if let offset = header.exth.coverOffset, let name = result.byNumber[offset + 1] { result.cover = name }
        return result
    }

    static func imageKind(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "gif" }
        if bytes.starts(with: [0x42, 0x4D]) { return "bmp" }
        return nil
    }

    // MARK: Text helpers

    static func decodeText(_ data: Data, encoding: Int) -> String {
        if encoding == 1252 { return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self) }
        return String(decoding: data, as: UTF8.self)
    }

    /// The part between <body> and </body>, or all of it.
    static func body(of html: String) -> String {
        var text = html
        if let open = text.range(of: "<body[^>]*>", options: [.regularExpression, .caseInsensitive]) { text = String(text[open.upperBound...]) }
        if let close = text.range(of: "</body>", options: [.caseInsensitive, .backwards]) { text = String(text[..<close.lowerBound]) }
        return text
    }

    /// The title of the chapter of a part: its first heading, its title, or a short first paragraph.
    /// A MOBI 6 book often makes its headings with a large font in a paragraph.
    static func heading(in html: String) -> String? {
        for pattern in [headingPattern, titlePattern, paragraphPattern] {
            guard let match = pattern.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html)
            else { continue }
            let text = strippedText(String(html[range]))
            if pattern === paragraphPattern && text.count > 80 { return nil }
            if !text.isEmpty { return String(text.prefix(120)) }
        }
        return nil
    }

    private static let headingPattern = try! NSRegularExpression(pattern: #"<h[1-3][^>]*>(.*?)</h[1-3]>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let titlePattern = try! NSRegularExpression(pattern: #"<title[^>]*>(.*?)</title>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let paragraphPattern = try! NSRegularExpression(pattern: #"<body[^>]*>\s*(?:<div[^>]*>\s*)*<p[^>]*>(.*?)</p>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])

    static func strippedText(_ html: String) -> String {
        let noTags = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&#160;", with: " ")
        return noTags.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func document(title: String?, body: String, styles: [String]) -> String {
        """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>\(XHTML.escape(title ?? ""))</title></head>
        <body>
        \(body)
        </body></html>
        """
    }

    /// Replaces each match of a pattern. The closure gets the match and its groups.
    static func replace(_ pattern: String, in text: String, with make: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        let ns = text as NSString
        var out = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let groups = (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : ns.substring(with: match.range(at: $0)) }
            out += make(groups)
            last = match.range.location + match.range.length
        }
        out += ns.substring(from: last)
        return out
    }
}

// MARK: - The containers

/// The records of a Palm database, the container of a MOBI file.
struct PalmDB {
    let data: Data
    let records: [Range<Int>]

    init(_ data: Data) throws {
        guard data.count >= 78 else { throw MOBIImporter.Failure.notMOBI }
        let type = String(decoding: data.subdata(in: 60..<68), as: UTF8.self)
        guard type == "BOOKMOBI" || type == "TEXtREAd" else { throw MOBIImporter.Failure.notMOBI }
        let count = Int(data.u16(76))
        guard data.count >= 78 + count * 8 else { throw MOBIImporter.Failure.notMOBI }
        let offsets = (0..<count).map { Int(data.u32(78 + $0 * 8)) }
        var records: [Range<Int>] = []
        for (index, offset) in offsets.enumerated() {
            let end = index + 1 < count ? offsets[index + 1] : data.count
            guard offset <= end, end <= data.count else { throw MOBIImporter.Failure.notMOBI }
            records.append(offset..<end)
        }
        self.data = data
        self.records = records
    }

    func record(_ index: Int) throws -> Data {
        guard records.indices.contains(index) else { throw MOBIImporter.Failure.notMOBI }
        return data.subdata(in: records[index])
    }
}

/// The facts of record 0: the PalmDOC header, the MOBI header, and the EXTH header.
struct Header {
    var compression: Int
    var textLength: Int
    var recordCount: Int
    var encryption: Int
    var encoding = 1252
    var version = 0
    var fullName: String?
    var firstImage: Int?
    var extraFlags = 0
    var fdstIndex: Int?
    var fragmentIndex: Int?
    var skeletonIndex: Int?
    var exth = EXTH()

    struct EXTH {
        var author: String?
        var summary: String?
        var title: String?
        var language: String?
        var coverOffset: Int?
        var boundary: Int?
    }

    init(_ record: Data) throws {
        guard record.count >= 16 else { throw MOBIImporter.Failure.notMOBI }
        compression = Int(record.u16(0))
        textLength = Int(record.u32(4))
        recordCount = Int(record.u16(8))
        encryption = Int(record.u16(12))
        // A plain PalmDOC book has no MOBI header.
        guard record.count >= 24, record.subdata(in: 16..<20) == Data("MOBI".utf8) else { return }
        let length = Int(record.u32(20))
        func field(_ offset: Int) -> Int? {
            guard offset + 4 <= 16 + length, offset + 4 <= record.count else { return nil }
            let value = record.u32(offset)
            return value == 0xFFFF_FFFF ? nil : Int(value)
        }
        encoding = field(28) ?? 1252
        version = field(36) ?? 0
        if let offset = field(84), let size = field(88), offset + size <= record.count {
            fullName = String(decoding: record.subdata(in: offset..<(offset + size)), as: UTF8.self).nonEmpty
        }
        firstImage = field(108)
        if length >= 0xE4, 16 + 0xE4 <= record.count { extraFlags = Int(record.u16(0xF2)) }
        if version >= 8 {
            fdstIndex = field(0xC0)
            fragmentIndex = field(0xF8)
            skeletonIndex = field(0xFC)
        }
        if let flags = field(0x80), flags & 0x40 != 0 {
            exth = Self.readEXTH(record, at: 16 + length, encoding: encoding)
        }
    }

    private static func readEXTH(_ record: Data, at start: Int, encoding: Int) -> EXTH {
        var exth = EXTH()
        guard start + 12 <= record.count, record.subdata(in: start..<(start + 4)) == Data("EXTH".utf8) else { return exth }
        let count = Int(record.u32(start + 8))
        var at = start + 12
        func text(_ data: Data) -> String? { MOBIImporter.decodeText(data, encoding: encoding).trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty }
        for _ in 0..<count {
            guard at + 8 <= record.count else { break }
            let type = Int(record.u32(at)), size = Int(record.u32(at + 4))
            guard size >= 8, at + size <= record.count else { break }
            let value = record.subdata(in: (at + 8)..<(at + size))
            switch type {
            case 100: exth.author = [exth.author, text(value)].compactMap { $0 }.joined(separator: ", ").nonEmpty
            case 103: exth.summary = text(value).map(EPUBImporter.stripTags)
            case 503: exth.title = text(value)
            case 524: exth.language = text(value)
            case 201 where value.count >= 4: exth.coverOffset = Int(value.u32(0))
            case 121 where value.count >= 4: exth.boundary = Int(value.u32(0))
            default: break
            }
            at += size
        }
        return exth
    }
}

/// An INDX index of KF8, such as the skeletons or the fragments.
enum Index {
    struct Entry {
        var name: String
        var tags: [Int: [Int]]
    }

    struct Tag {
        var tag: Int
        var valuesPerEntry: Int
        var mask: Int
        var end: Bool
    }

    /// The entries of the index that starts at a record.
    static func read(_ db: PalmDB, at index: Int) throws -> [Entry] {
        let head = try db.record(index)
        guard head.prefix(4) == Data("INDX".utf8), head.count >= 28 else { return [] }
        let length = Int(head.u32(4))
        let records = Int(head.u32(24))
        guard length + 12 <= head.count, head.subdata(in: length..<(length + 4)) == Data("TAGX".utf8) else { return [] }
        let tagxLength = Int(head.u32(length + 4))
        let controlBytes = Int(head.u32(length + 8))
        var tags: [Tag] = []
        var at = length + 12
        while at + 4 <= length + tagxLength {
            tags.append(Tag(tag: Int(head[head.startIndex + at]), valuesPerEntry: Int(head[head.startIndex + at + 1]),
                            mask: Int(head[head.startIndex + at + 2]), end: head[head.startIndex + at + 3] == 1))
            at += 4
        }
        var entries: [Entry] = []
        for number in 1...max(records, 1) where index + number < db.records.count {
            entries += try readRecord(try db.record(index + number), tags: tags, controlBytes: controlBytes)
        }
        return entries
    }

    static func readRecord(_ record: Data, tags: [Tag], controlBytes: Int) throws -> [Entry] {
        let bytes = [UInt8](record)
        guard bytes.count >= 28, record.prefix(4) == Data("INDX".utf8) else { return [] }
        let idxt = Int(record.u32(20))
        let count = Int(record.u32(24))
        guard idxt + 4 + count * 2 <= bytes.count else { return [] }
        let offsets = (0..<count).map { Int(record.u16(idxt + 4 + $0 * 2)) }
        var entries: [Entry] = []
        for (number, offset) in offsets.enumerated() {
            let end = number + 1 < count ? offsets[number + 1] : idxt
            guard offset < end, end <= bytes.count else { continue }
            let nameLength = Int(bytes[offset])
            guard offset + 1 + nameLength <= end else { continue }
            let name = String(decoding: bytes[(offset + 1)..<(offset + 1 + nameLength)], as: UTF8.self)
            let start = offset + 1 + nameLength
            guard start + controlBytes <= end else { continue }
            let control = Array(bytes[start..<(start + controlBytes)])
            entries.append(Entry(name: name, tags: values(Array(bytes[(start + controlBytes)..<end]), tags: tags, control: control)))
        }
        return entries
    }

    /// The values of the tags of one entry, from its control bytes and its numbers.
    static func values(_ data: [UInt8], tags: [Tag], control: [UInt8]) -> [Int: [Int]] {
        var plan: [(tag: Int, count: Int?, bytes: Int?, perEntry: Int)] = []
        var byte = 0
        var at = 0
        for tag in tags {
            if tag.end {
                byte += 1
                continue
            }
            guard byte < control.count else { break }
            var value = Int(control[byte]) & tag.mask
            guard value != 0 else { continue }
            if value == tag.mask {
                if tag.mask.nonzeroBitCount > 1 {
                    let (size, read) = varint(data, at: at)
                    at += read
                    plan.append((tag.tag, nil, size, tag.valuesPerEntry))
                } else {
                    plan.append((tag.tag, 1, nil, tag.valuesPerEntry))
                }
            } else {
                var mask = tag.mask
                while mask & 1 == 0 {
                    mask >>= 1
                    value >>= 1
                }
                plan.append((tag.tag, value, nil, tag.valuesPerEntry))
            }
        }
        var result: [Int: [Int]] = [:]
        for step in plan {
            var values: [Int] = []
            if let count = step.count {
                for _ in 0..<(count * step.perEntry) where at < data.count {
                    let (value, read) = varint(data, at: at)
                    at += read
                    values.append(value)
                }
            } else if let bytes = step.bytes {
                var used = 0
                while used < bytes, at < data.count {
                    let (value, read) = varint(data, at: at)
                    at += read
                    used += read
                    values.append(value)
                }
            }
            result[step.tag] = values
        }
        return result
    }

    /// A number in 7-bit bytes. The last byte has the high bit.
    static func varint(_ data: [UInt8], at start: Int) -> (value: Int, read: Int) {
        var value = 0
        var at = start
        while at < data.count {
            let byte = data[at]
            value = (value << 7) | Int(byte & 0x7F)
            at += 1
            if byte & 0x80 != 0 { break }
        }
        return (value, at - start)
    }
}

extension Data {
    func u16(_ offset: Int) -> UInt16 {
        let i = startIndex + offset
        return UInt16(self[i]) << 8 | UInt16(self[i + 1])
    }

    func u32(_ offset: Int) -> UInt32 {
        let i = startIndex + offset
        return UInt32(self[i]) << 24 | UInt32(self[i + 1]) << 16 | UInt32(self[i + 2]) << 8 | UInt32(self[i + 3])
    }
}
