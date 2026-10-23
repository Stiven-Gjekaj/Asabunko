import Foundation

/// A page of an OPDS catalog: OPDS 1.2 in Atom, or OPDS 2.0 in JSON.
public struct OPDSFeed: Sendable, Equatable {
    public var title: String
    /// The links to other feeds, such as "Series" or "Latest".
    public var navigation: [OPDSLink]
    /// The books of this page.
    public var publications: [OPDSPublication]
    /// The groups of an OPDS 2.0 feed, each with a title.
    public var groups: [OPDSGroup]
    public var next: URL?
    /// The template of a search URL, with {searchTerms} or {?query}, or a link to an OpenSearch description.
    public var search: OPDSSearch?

    public init(title: String, navigation: [OPDSLink] = [], publications: [OPDSPublication] = [], groups: [OPDSGroup] = [], next: URL? = nil, search: OPDSSearch? = nil) {
        self.title = title
        self.navigation = navigation
        self.publications = publications
        self.groups = groups
        self.next = next
        self.search = search
    }
}

public struct OPDSGroup: Sendable, Equatable {
    public var title: String
    public var navigation: [OPDSLink]
    public var publications: [OPDSPublication]
}

public struct OPDSLink: Sendable, Equatable, Hashable {
    public var title: String
    public var url: URL
    public var summary: String?
}

public enum OPDSSearch: Sendable, Equatable {
    case template(String)
    /// A link to an OpenSearch description, which holds the template.
    case description(URL)
}

public struct OPDSPublication: Sendable, Equatable, Identifiable {
    public struct Acquisition: Sendable, Equatable {
        public var url: URL
        public var type: String
    }

    /// The pages of a comic one at a time, with the Page Streaming Extension.
    public struct Stream: Sendable, Equatable {
        /// The URL with {pageNumber}, from 0, and maybe {maxWidth}.
        public var template: String
        public var count: Int

        public func url(page: Int, maxWidth: Int = 1600) -> URL? {
            URL(string: template.replacingOccurrences(of: "{pageNumber}", with: String(page))
                .replacingOccurrences(of: "{maxWidth}", with: String(maxWidth)))
        }
    }

    public var id: String
    public var title: String
    public var author: String?
    public var summary: String?
    public var image: URL?
    public var acquisitions: [Acquisition]
    public var stream: Stream?

    /// The first acquisition that Asabunko can import, with the extension of its file.
    public var download: (url: URL, fileExtension: String)? {
        for acquisition in acquisitions {
            if let ext = OPDS.fileExtension(for: acquisition.type, url: acquisition.url) { return (acquisition.url, ext) }
        }
        return nil
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.title == b.title && a.author == b.author && a.summary == b.summary
            && a.image == b.image && a.acquisitions == b.acquisitions && a.stream == b.stream
    }
}

public enum OPDSError: Error, Equatable {
    case notAFeed
}

public enum OPDS {
    static let streamRel = "http://vaemendis.net/opds-pse/stream"

    /// Reads a feed of either version. `base` resolves the relative links.
    public static func parse(_ data: Data, base: URL) throws -> OPDSFeed {
        let first = data.first(where: { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 || $0 == 0xEF || $0 == 0xBB || $0 == 0xBF) })
        if first == UInt8(ascii: "{") { return try parseJSON(data, base: base) }
        return try parseAtom(data, base: base)
    }

    /// The extension of the file for a MIME type, or nil when the app cannot import it.
    public static func fileExtension(for type: String, url: URL) -> String? {
        let mime = type.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        switch mime {
        case "application/epub+zip": return "epub"
        case "application/pdf": return "pdf"
        case "application/x-cbz", "application/vnd.comicbook+zip": return "cbz"
        case "application/x-cbr", "application/vnd.comicbook-rar": return "cbr"
        case "application/x-cb7": return "cb7"
        case "application/zip", "application/x-zip-compressed": return "cbz"
        case "application/x-rar-compressed", "application/vnd.rar": return "cbr"
        case "application/x-fictionbook+xml", "text/fb2+xml": return "fb2"
        case "text/plain": return "txt"
        // Project Gutenberg gives its Kindle files with these types, and with no extension in the link.
        case "application/x-mobipocket-ebook": return "mobi"
        case "application/vnd.amazon.mobi8-ebook", "application/vnd.amazon.ebook": return "azw3"
        default:
            let ext = url.pathExtension.lowercased()
            return BookImporter.supportedExtensions.contains(ext) ? ext : nil
        }
    }

    /// The URL of a search, from a template with {searchTerms} (OPDS 1) or {?query} (OPDS 2).
    public static func searchURL(template: String, query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? query
        var text = template.replacingOccurrences(of: "{searchTerms}", with: encoded)
        if let range = text.range(of: "{?query}") {
            let joiner = text[..<range.lowerBound].contains("?") ? "&" : "?"
            text.replaceSubrange(range, with: joiner + "query=" + encoded)
        }
        text = text.replacingOccurrences(of: "{query}", with: encoded)
        // The other parameters of a template, such as {startPage?}, are not used.
        text = text.replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
        return URL(string: text)
    }

    /// The template of an OpenSearch description for Atom results.
    public static func openSearchTemplate(_ data: Data) -> String? {
        guard let root = XMLElement.parse(data) else { return nil }
        let urls = root.children("Url")
        return (urls.first { ($0["type"] ?? "").contains("atom") } ?? urls.first)?["template"]
    }

    /// Makes a link absolute as text. A template keeps its braces, which `URL` does not take.
    static func absolute(_ href: String, base: URL) -> String {
        if href.hasPrefix("http://") || href.hasPrefix("https://") { return href }
        var origin = "\(base.scheme ?? "https")://\(base.host ?? "")"
        if let port = base.port { origin += ":\(port)" }
        if href.hasPrefix("/") { return origin + href }
        let directory = base.path.hasSuffix("/") ? base.path : (base.path as NSString).deletingLastPathComponent
        return origin + (directory.hasSuffix("/") ? directory : directory + "/") + href
    }

    // MARK: OPDS 1.2

    static func parseAtom(_ data: Data, base: URL) throws -> OPDSFeed {
        guard let root = XMLElement.parse(data), root.name == "feed" else { throw OPDSError.notAFeed }
        func resolve(_ href: String?) -> URL? {
            guard let href, !href.isEmpty else { return nil }
            return URL(string: href, relativeTo: base)?.absoluteURL
        }
        var feed = OPDSFeed(title: root.child("title")?.allText.nonEmpty ?? "Catalog")
        for link in root.children("link") {
            let rel = link["rel"] ?? "", type = link["type"] ?? ""
            if rel == "next" { feed.next = resolve(link["href"]) }
            if rel == "search", let href = link["href"] {
                if type.contains("opensearchdescription"), let url = resolve(href) {
                    feed.search = .description(url)
                } else {
                    feed.search = .template(absolute(href, base: base))
                }
            }
        }
        for entry in root.children("entry") {
            let title = entry.child("title")?.allText.nonEmpty ?? "Untitled"
            let links = entry.children("link")
            var acquisitions: [OPDSPublication.Acquisition] = []
            var image: URL?, thumbnail: URL?, stream: OPDSPublication.Stream?, navigation: URL?
            for link in links {
                let rel = link["rel"] ?? "", type = link["type"] ?? ""
                if rel.contains("opds-spec.org/acquisition"), let url = resolve(link["href"]) {
                    acquisitions.append(.init(url: url, type: type))
                } else if rel == "http://opds-spec.org/image" {
                    image = resolve(link["href"])
                } else if rel == "http://opds-spec.org/image/thumbnail" {
                    thumbnail = resolve(link["href"])
                } else if rel == streamRel, let href = link["href"] {
                    stream = .init(template: absolute(href, base: base), count: Int(link["count"] ?? link["pse:count"] ?? "") ?? 0)
                } else if type.contains("application/atom+xml") || type.contains("opds-catalog") {
                    navigation = navigation ?? resolve(link["href"])
                }
            }
            if acquisitions.isEmpty && stream == nil, let navigation {
                feed.navigation.append(OPDSLink(title: title, url: navigation, summary: entry.child("content")?.allText.nonEmpty ?? entry.child("summary")?.allText.nonEmpty))
                continue
            }
            let author = entry.children("author").compactMap { $0.child("name")?.allText.nonEmpty }.joined(separator: ", ").nonEmpty
            let summary = (entry.child("summary") ?? entry.child("content"))?.allText.nonEmpty.map(EPUBImporter.stripTags)
            feed.publications.append(OPDSPublication(
                id: entry.child("id")?.allText.nonEmpty ?? title, title: title, author: author, summary: summary,
                image: thumbnail ?? image, acquisitions: acquisitions, stream: stream
            ))
        }
        return feed
    }

    // MARK: OPDS 2.0

    static func parseJSON(_ data: Data, base: URL) throws -> OPDSFeed {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw OPDSError.notAFeed }
        func resolve(_ href: Any?) -> URL? {
            guard let href = href as? String, !href.isEmpty else { return nil }
            return URL(string: href, relativeTo: base)?.absoluteURL
        }
        func links(_ value: Any?) -> [[String: Any]] { value as? [[String: Any]] ?? [] }
        func navigation(_ value: Any?) -> [OPDSLink] {
            links(value).compactMap { link in
                resolve(link["href"]).map { OPDSLink(title: link["title"] as? String ?? "Untitled", url: $0, summary: nil) }
            }
        }
        func publications(_ value: Any?) -> [OPDSPublication] {
            links(value).map { item in
                let metadata = item["metadata"] as? [String: Any] ?? [:]
                let title = metadata["title"] as? String ?? "Untitled"
                let authors: [Any] = (metadata["author"] as? [Any]) ?? (metadata["author"].map { [$0] } ?? [])
                let author = authors.compactMap { ($0 as? String) ?? (($0 as? [String: Any])?["name"] as? String) }.joined(separator: ", ").nonEmpty
                var acquisitions: [OPDSPublication.Acquisition] = []
                for link in links(item["links"]) {
                    let rel = (link["rel"] as? String) ?? ((link["rel"] as? [String])?.joined(separator: " ")) ?? ""
                    if rel.contains("acquisition"), let url = resolve(link["href"]) {
                        acquisitions.append(.init(url: url, type: link["type"] as? String ?? ""))
                    }
                }
                let image = links(item["images"]).first.flatMap { resolve($0["href"]) }
                return OPDSPublication(
                    id: metadata["identifier"] as? String ?? title, title: title, author: author,
                    summary: (metadata["description"] as? String).map(EPUBImporter.stripTags),
                    image: image, acquisitions: acquisitions, stream: nil
                )
            }
        }
        let metadata = root["metadata"] as? [String: Any] ?? [:]
        var feed = OPDSFeed(
            title: metadata["title"] as? String ?? "Catalog",
            navigation: navigation(root["navigation"]),
            publications: publications(root["publications"])
        )
        for group in links(root["groups"]) {
            let title = (group["metadata"] as? [String: Any])?["title"] as? String ?? ""
            feed.groups.append(OPDSGroup(title: title, navigation: navigation(group["navigation"]), publications: publications(group["publications"])))
        }
        for link in links(root["links"]) {
            let rel = link["rel"] as? String ?? ""
            if rel == "next" { feed.next = resolve(link["href"]) }
            if rel == "search", let href = link["href"] as? String {
                feed.search = .template(absolute(href, base: base))
            }
        }
        return feed
    }
}

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+?#")
        return set
    }()
}
