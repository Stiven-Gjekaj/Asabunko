import Foundation

/// The data of the Aidoku sources, in the order of the fields of aidoku-rs (MIT License),
/// crates/lib/src/structs/mod.rs. Postcard has no names, so the order of the fields is the format.
enum Aidoku {
    struct Manga: Equatable {
        var key: String
        var title: String
        var cover: String?
        var artists: [String]?
        var authors: [String]?
        var description: String?
        var url: String?
        var tags: [String]?
        var status: UInt64 = 0
        var contentRating: UInt64 = 0
        var viewer: UInt64 = 0
        var updateStrategy: UInt64 = 0
        var nextUpdateTime: Int64?
        var chapters: [Chapter]?

        func write(_ w: inout PostcardWriter) {
            w.string(key)
            w.string(title)
            w.option(cover) { $0.string($1) }
            w.option(artists) { $0.list($1) { $0.string($1) } }
            w.option(authors) { $0.list($1) { $0.string($1) } }
            w.option(description) { $0.string($1) }
            w.option(url) { $0.string($1) }
            w.option(tags) { $0.list($1) { $0.string($1) } }
            w.varint(status)
            w.varint(contentRating)
            w.varint(viewer)
            w.varint(updateStrategy)
            w.option(nextUpdateTime) { $0.signed($1) }
            w.option(chapters) { $0.list($1) { $1.write(&$0) } }
        }

        static func read(_ r: inout PostcardReader) throws -> Manga {
            Manga(
                key: try r.string(), title: try r.string(), cover: try r.option { try $0.string() },
                artists: try r.option { try $0.list { try $0.string() } }, authors: try r.option { try $0.list { try $0.string() } },
                description: try r.option { try $0.string() }, url: try r.option { try $0.string() },
                tags: try r.option { try $0.list { try $0.string() } },
                status: try r.varint(), contentRating: try r.varint(), viewer: try r.varint(), updateStrategy: try r.varint(),
                nextUpdateTime: try r.option { try $0.signed() }, chapters: try r.option { try $0.list { try Chapter.read(&$0) } }
            )
        }

        /// The status in words, from the variants of MangaStatus.
        var statusName: String? {
            ["Ongoing", "Completed", "Cancelled", "Hiatus"].indices.contains(Int(status) - 1) ? ["Ongoing", "Completed", "Cancelled", "Hiatus"][Int(status) - 1] : nil
        }
    }

    struct Chapter: Equatable {
        var key: String
        var title: String?
        var chapterNumber: Float?
        var volumeNumber: Float?
        var dateUploaded: Int64?
        var scanlators: [String]?
        var url: String?
        var language: String?
        var thumbnail: String?
        var locked: Bool = false

        func write(_ w: inout PostcardWriter) {
            w.string(key)
            w.option(title) { $0.string($1) }
            w.option(chapterNumber) { $0.f32($1) }
            w.option(volumeNumber) { $0.f32($1) }
            w.option(dateUploaded) { $0.signed($1) }
            w.option(scanlators) { $0.list($1) { $0.string($1) } }
            w.option(url) { $0.string($1) }
            w.option(language) { $0.string($1) }
            w.option(thumbnail) { $0.string($1) }
            w.bool(locked)
        }

        static func read(_ r: inout PostcardReader) throws -> Chapter {
            Chapter(
                key: try r.string(), title: try r.option { try $0.string() }, chapterNumber: try r.option { try $0.f32() },
                volumeNumber: try r.option { try $0.f32() }, dateUploaded: try r.option { try $0.signed() },
                scanlators: try r.option { try $0.list { try $0.string() } }, url: try r.option { try $0.string() },
                language: try r.option { try $0.string() }, thumbnail: try r.option { try $0.string() }, locked: try r.bool()
            )
        }

        /// "Vol. 2 Ch. 12: The Rain", "Ch. 12", or the title of the source.
        var displayTitle: String {
            func number(_ value: Float) -> String { value == value.rounded() ? String(Int(value)) : String(value) }
            var parts: [String] = []
            if let volumeNumber { parts.append("Vol. \(number(volumeNumber))") }
            if let chapterNumber { parts.append("Ch. \(number(chapterNumber))") }
            let head = parts.joined(separator: " ")
            guard let title = title?.nonEmpty else { return head.isEmpty ? key : head }
            return head.isEmpty ? title : "\(head): \(title)"
        }
    }

    struct MangaPageResult {
        var entries: [Manga]
        var hasNextPage: Bool

        static func read(_ r: inout PostcardReader) throws -> MangaPageResult {
            MangaPageResult(entries: try r.list { try Manga.read(&$0) }, hasNextPage: try r.bool())
        }
    }

    struct Listing: Equatable {
        var id: String
        var name: String
        var kind: UInt64 = 0

        func write(_ w: inout PostcardWriter) {
            w.string(id)
            w.string(name)
            w.varint(kind)
        }

        static func read(_ r: inout PostcardReader) throws -> Listing {
            Listing(id: try r.string(), name: try r.string(), kind: try r.varint())
        }
    }

    enum PageContent: Equatable {
        case url(String, [String: String]?)
        case text(String)
        case image(Int32)
        case zip(String, String)
    }

    struct Page: Equatable {
        var content: PageContent
        var thumbnail: String?
        var hasDescription: Bool
        var description: String?

        static func read(_ r: inout PostcardReader) throws -> Page {
            let content: PageContent
            switch try r.varint() {
            case 0: content = .url(try r.string(), try r.option { try readMap(&$0) })
            case 1: content = .text(try r.string())
            case 2: content = .image(Int32(truncatingIfNeeded: try r.signed()))
            case 3: content = .zip(try r.string(), try r.string())
            case let tag: throw PostcardError.badTag(tag)
            }
            return Page(content: content, thumbnail: try r.option { try $0.string() }, hasDescription: try r.bool(), description: try r.option { try $0.string() })
        }
    }

    static func readMap(_ r: inout PostcardReader) throws -> [String: String] {
        var map: [String: String] = [:]
        for _ in 0..<(try r.unsigned()) { map[try r.string()] = try r.string() }
        return map
    }

    static func writeMap(_ map: [String: String], _ w: inout PostcardWriter) {
        w.unsigned(map.count)
        for (key, value) in map.sorted(by: { $0.key < $1.key }) {
            w.string(key)
            w.string(value)
        }
    }
}
