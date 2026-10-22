import Foundation

/// The kinds of source that a line of the source list can be.
public enum SourceKind: String, Codable, Sendable, CaseIterable {
    /// An OPDS catalog, such as Komga, Kavita, Calibre-web, or Suwayomi.
    case opds
    /// A list of LNReader plugins, for novels on the web.
    case lnreader
    /// A list of Aidoku sources.
    case aidoku
    /// A repository of Paperback 0.9 extensions.
    case paperback
    /// A Suwayomi server, which runs the extensions of Mihon.
    case suwayomi

    public var name: String {
        switch self {
        case .opds: "OPDS catalog"
        case .lnreader: "LNReader plugins"
        case .aidoku: "Aidoku sources"
        case .paperback: "Paperback extensions"
        case .suwayomi: "Suwayomi server"
        }
    }

    /// The kind that the URL tells, or nil when only its content can tell.
    public static func guess(_ url: URL) -> SourceKind? {
        let text = url.absoluteString.lowercased()
        let path = url.path.lowercased()
        if path.hasSuffix("plugins.min.json") || path.hasSuffix("plugins.json") || text.contains("lnreader") { return .lnreader }
        if path.hasSuffix("versioning.json") || text.contains("paperback") || text.contains("inkdex") { return .paperback }
        if path.hasSuffix("index.min.json") || text.contains("aidoku") { return .aidoku }
        if path.contains("/opds") { return .opds }
        if text.contains("suwayomi") || text.contains("tachidesk") || url.port == 4567 || path.hasSuffix("/api/graphql") { return .suwayomi }
        return nil
    }

    /// The kind that the content of the URL tells.
    public static func detect(_ data: Data) -> SourceKind? {
        let head = String(decoding: data.prefix(4096), as: UTF8.self)
        if head.contains("<feed") || head.contains("opds") && head.contains("\"metadata\"") { return .opds }
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let object = json as? [String: Any] {
            if object["builtWith"] != nil || object["repository"] != nil && object["sources"] != nil { return .paperback }
            if object["sources"] is [Any] { return .aidoku }
            if object["navigation"] != nil || object["publications"] != nil { return .opds }
        }
        if let array = json as? [[String: Any]], let first = array.first {
            if first["site"] != nil || (first["url"] as? String)?.hasSuffix(".js") == true { return .lnreader }
            if first["file"] != nil || first["downloadURL"] != nil { return .aidoku }
        }
        return nil
    }
}

/// One line of the source list. A password is not here. It is in the Keychain of the device.
public struct SourceLink: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: UUID
    /// The URL with no user name and no password.
    public var url: URL
    public var username: String?
    /// The kind, or nil until the app reads the content of the URL.
    public var kind: SourceKind?
    /// The name that the source gives, such as the title of a catalog.
    public var name: String?

    public init(id: UUID = UUID(), url: URL, username: String? = nil, kind: SourceKind? = nil, name: String? = nil) {
        self.id = id
        self.url = url
        self.username = username
        self.kind = kind
        self.name = name
    }

    /// The scheme and the host only. A URL can hold a key in its path.
    public var shortAddress: String {
        "\(url.scheme ?? "https")://\(url.host ?? "")\(url.port.map { ":\($0)" } ?? "")/..."
    }
}

/// The source list as text, one URL on each line, as in ZettaStream.
/// "https://user:password@host/opds" gives a user name and a password.
public enum SourceList {
    public struct Line: Equatable, Sendable {
        public var link: SourceLink
        /// The password of the line, or nil when the line has none.
        public var password: String?
    }

    /// Reads the text. Empty lines, lines that start with "#", and lines that are not URLs are skipped.
    /// A line that is two times in the text is one source.
    /// `existing` keeps the ID, the kind, and the name of each source that stays.
    public static func parse(_ text: String, existing: [SourceLink] = []) -> [Line] {
        var lines: [Line] = []
        var seen = Set<String>()
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"),
                  var parts = URLComponents(string: line.contains("://") ? line : "https://" + line),
                  parts.scheme == "http" || parts.scheme == "https", parts.host?.isEmpty == false
            else { continue }
            let username = parts.user?.removingPercentEncoding
            let password = parts.password?.removingPercentEncoding
            parts.user = nil
            parts.password = nil
            guard let url = parts.url else { continue }
            let key = url.absoluteString + "|" + (username ?? "")
            guard seen.insert(key).inserted else { continue }
            let old = existing.first { $0.url == url && $0.username == username }
            let link = SourceLink(
                id: old?.id ?? UUID(), url: url, username: username,
                kind: old?.kind ?? SourceKind.guess(url), name: old?.name
            )
            lines.append(Line(link: link, password: password))
        }
        return lines
    }

    /// The text of the list. A user name stays in its line, but a password does not.
    public static func format(_ links: [SourceLink]) -> String {
        links.map { link in
            guard let user = link.username, var parts = URLComponents(url: link.url, resolvingAgainstBaseURL: false) else {
                return link.url.absoluteString
            }
            parts.user = user
            return parts.url?.absoluteString ?? link.url.absoluteString
        }.joined(separator: "\n")
    }
}
