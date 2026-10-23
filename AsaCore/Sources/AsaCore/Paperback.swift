import CommonCrypto
import CryptoKit
import Foundation
import JavaScriptCore
import SwiftSoup

/// The repository of Paperback 0.9 extensions: versioning.json, with each extension in <Id>/index.js.
public enum PaperbackIndex {
    private struct Repository: Decodable {
        struct Source: Decodable {
            let id: String
            let name: String
            let version: String
            let icon: String?
            let language: String?
            let contentRating: String?
            let capabilities: Capabilities?
        }
        /// A list of flags, or one integer with the flags.
        struct Capabilities: Decodable {
            let mask: Int
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let list = try? c.decode([Int].self) { mask = list.reduce(0, |) } else { mask = try c.decode(Int.self) }
            }
        }
        let sources: [Source]
    }

    /// The extensions that give chapters and a search. A tracker, such as AniList, is not a reader.
    public static func parse(_ data: Data, url: URL) throws -> [SourceInfo] {
        let base = url.lastPathComponent == "versioning.json" ? url.deletingLastPathComponent() : url
        return try JSONDecoder().decode(Repository.self, from: data).sources.compactMap { source in
            let mask = source.capabilities?.mask ?? 65
            guard mask & 1 != 0, mask & 64 != 0 else { return nil }
            let folder = base.appendingPathComponent(source.id, isDirectory: true)
            return SourceInfo(
                id: source.id, name: source.name, language: source.language ?? "", version: source.version,
                icon: source.icon.map { folder.appendingPathComponent("static").appendingPathComponent($0) },
                code: folder.appendingPathComponent("index.js"), novels: false, adult: source.contentRating == "ADULT"
            )
        }
    }
}

/// One Paperback 0.9 extension in its own JavaScript context.
public final class PaperbackExtension: OnlineSource, @unchecked Sendable {
    public let info: SourceInfo
    private let runtime: JSRuntime
    private let state: PaperbackState
    private var sections: [Section] = []
    private var coverHeaders: [String: String]?
    private let lock = NSLock()

    struct Section: Decodable { let id: String; let title: String; let type: Int }

    public init(info: SourceInfo, code: String, stateFile: URL?, userAgent: String, fetcher: @escaping Fetcher) async throws {
        self.info = info
        runtime = try JSRuntime(name: "paperback.\(info.id)", fetcher: fetcher)
        state = PaperbackState(file: stateFile)
        Self.installNatives(runtime, state: state, userAgent: userAgent)
        guard let prelude = Bundle.module.url(forResource: "paperback", withExtension: "js") else { throw JSRuntimeError.script("No paperback.js") }
        try runtime.evaluate(try String(contentsOf: prelude, encoding: .utf8), url: "paperback.js")
        try runtime.evaluate(code, url: "\(info.id)/index.js")
        struct Started: Decodable { let sections: [Section] }
        sections = try await runtime.invoke(Started.self, "__paperback.start", [info.id]).sections
    }

    private func section(_ words: [String], type: Int? = nil) -> Section? {
        sections.first { section in
            (type != nil && section.type == type) || words.contains { (section.id + " " + section.title).lowercased().contains($0) }
        }
    }

    private var popularSection: Section? { section(["popular", "trend", "hot", "top"]) }
    private var latestSection: Section? { section(["latest", "update", "recent", "new"], type: 3) }

    public var canShowLatest: Bool { latestSection != nil }

    private struct Page: Decodable {
        struct Item: Decodable { let id: String; let title: String; let cover: String? }
        let items: [Item]
        let hasMore: Bool
    }

    private func page(_ function: String, _ arguments: [Any]) async throws -> OnlinePage {
        let page = try await runtime.invoke(Page.self, function, arguments)
        // The headers of the covers come from the interceptors of the extension, such as a referer.
        if lock.withLock({ coverHeaders }) == nil, let first = page.items.compactMap(\.cover).first {
            let headers = (try? await runtime.invoke([String: String].self, "__paperback.imageHeaders", [first])) ?? [:]
            lock.withLock { coverHeaders = headers }
        }
        return OnlinePage(items: page.items.map { OnlineSeries(id: $0.id, title: $0.title, cover: $0.cover.flatMap { URL(lenient: $0) }) }, hasMore: page.hasMore)
    }

    public func popular(page number: Int) async throws -> OnlinePage {
        if let popularSection { return try await page("__paperback.section", [popularSection.id, number]) }
        return try await page("__paperback.search", ["", number])
    }

    public func latest(page number: Int) async throws -> OnlinePage {
        guard let latestSection else { return try await popular(page: number) }
        return try await page("__paperback.section", [latestSection.id, number])
    }

    public func search(_ query: String, page number: Int) async throws -> OnlinePage {
        try await page("__paperback.search", [query, number])
    }

    public func filterOptions() async -> [SourceOption] {
        guard let data = try? await runtime.invoke("__paperback.filters"),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return list.compactMap { filter in
            guard let id = filter["id"] as? String, let type = filter["type"] as? String else { return nil }
            let title = filter["title"] as? String ?? id
            let choices = (filter["options"] as? [[String: Any]] ?? []).map { SourceOption.Choice(label: $0["label"] as? String ?? "", value: $0["value"] as? String ?? "") }
            switch type {
            case "input":
                return SourceOption(id: id, title: title, kind: .text(placeholder: filter["placeholder"] as? String), initial: .text(filter["value"] as? String ?? ""), raw: type)
            case "dropdown" where !choices.isEmpty:
                return SourceOption(id: id, title: title, kind: .select(choices), initial: .select(filter["value"] as? String ?? choices[0].value), raw: type)
            case "multiselect" where !choices.isEmpty:
                let marks = filter["value"] as? [String: String] ?? [:]
                return SourceOption(id: id, title: title, kind: .multi(choices, excludable: filter["allowExclusion"] as? Bool ?? false),
                                    initial: .multi(included: marks.filter { $0.value == "included" }.map(\.key).sorted(),
                                                    excluded: marks.filter { $0.value == "excluded" }.map(\.key).sorted()), raw: type)
            default:
                return nil
            }
        }
    }

    public func browse(page number: Int, query: String, filters: [String: OptionValue]) async throws -> OnlinePage {
        guard !filters.isEmpty else { return query.isEmpty ? try await popular(page: number) : try await search(query, page: number) }
        var values: [String: Any] = [:]
        for (id, value) in filters {
            switch value {
            case let .text(text): values[id] = text
            case let .select(choice): values[id] = choice
            case let .multi(included, excluded):
                var marks: [String: String] = [:]
                for choice in included { marks[choice] = "included" }
                for choice in excluded { marks[choice] = "excluded" }
                values[id] = marks
            case let .toggle(on): values[id] = on
            case let .sort(index, _): values[id] = index
            case let .range(from, to): values[id] = ["from": from ?? NSNull(), "to": to ?? NSNull()] as [String: Any]
            }
        }
        let json = String(decoding: try JSONSerialization.data(withJSONObject: values), as: UTF8.self)
        return try await page("__paperback.browse", [query, json, number])
    }

    public func hasSettingsForm() async -> Bool {
        (try? await runtime.invoke(Bool.self, "__paperback.hasForm")) ?? false
    }

    public func settingsForm() async throws -> SourceForm? {
        try await runtime.invoke(SourceForm?.self, "__paperback.settingsForm")
    }

    public func form(_ id: String) async throws -> SourceForm {
        try await runtime.invoke(SourceForm.self, "__paperback.form", [id])
    }

    public func formAction(_ form: String, row: String, input: FormInput) async throws -> SourceForm {
        let value: Any = switch input {
        case .tap: NSNull()
        case let .text(text): text
        case let .toggle(on): on
        case let .number(number): number
        case .login, .web, .callback, .logout: throw SourceFormError.unknownRow
        }
        // A fragment of JSON in an array, because JSONSerialization does not write a single value with no options.
        let json = String(decoding: try JSONSerialization.data(withJSONObject: [value]), as: UTF8.self).dropFirst().dropLast()
        return try await runtime.invoke(SourceForm.self, "__paperback.formAction", [form, row, String(json)])
    }

    public func submitForm(_ id: String) async throws {
        _ = try await runtime.invoke("__paperback.formSubmit", [id])
    }

    private struct Details: Decodable {
        struct Chapter: Decodable {
            let id: String
            let title: String?
            let number: Double?
            let volume: Double?
            let group: String?
            let date: String?
            let index: Double?
        }
        let title: String
        let cover: String?
        let summary: String?
        let author: String?
        let status: String?
        let tags: [String]
        let novel: Bool
        let chapters: [Chapter]
    }

    public func details(of series: OnlineSeries) async throws -> OnlineDetails {
        let details = try await runtime.invoke(Details.self, "__paperback.details", [series.id])
        return OnlineDetails(
            series: OnlineSeries(id: series.id, title: details.title, cover: details.cover.flatMap { URL(lenient: $0) } ?? series.cover),
            author: details.author, summary: details.summary.map(EPUBImporter.stripTags)?.nonEmpty, status: details.status?.nonEmpty,
            genres: details.tags,
            chapters: Self.ordered(details.chapters).map { chapter in
                OnlineChapter(id: chapter.id, title: Self.title(of: chapter), number: chapter.number, date: chapter.date, group: chapter.group)
            },
            isNovel: details.novel
        )
    }

    /// The chapters from the oldest to the newest. The direction of the order of a source is not fixed,
    /// so the numbers of the chapters decide it. With no numbers, the newest comes first, as most sources give it.
    private static func ordered(_ chapters: [Details.Chapter]) -> [Details.Chapter] {
        let numbered = chapters.compactMap(\.number)
        if numbered.count >= 2 {
            let rising = zip(numbered, numbered.dropFirst()).filter { $0 < $1 }.count
            let falling = zip(numbered, numbered.dropFirst()).filter { $0 > $1 }.count
            return rising >= falling ? chapters : chapters.reversed()
        }
        return chapters.reversed()
    }

    private static func title(of chapter: Details.Chapter) -> String {
        func number(_ value: Double) -> String { value == value.rounded() ? String(Int(value)) : String(value) }
        var parts: [String] = []
        if let volume = chapter.volume, volume > 0 { parts.append("Vol. \(number(volume))") }
        if let value = chapter.number, value >= 0 { parts.append("Ch. \(number(value))") }
        let head = parts.joined(separator: " ")
        // A title such as "Chapter 12" only says the number again.
        let repeats = chapter.number.map { value in
            chapter.title?.range(of: "^(chapter|ch\\.?|episode|ep\\.?)\\s*0*\(number(value))$", options: [.regularExpression, .caseInsensitive]) != nil
        } ?? false
        guard let title = chapter.title?.nonEmpty, title != head, !repeats else { return head.isEmpty ? "Chapter" : head }
        return head.isEmpty ? title : "\(head): \(title)"
    }

    private struct Content: Decodable {
        struct Request: Decodable { let url: String; let headers: [String: String] }
        let html: String?
        let pages: [Request]?
    }

    public func content(of chapter: OnlineChapter, in series: OnlineSeries) async throws -> ChapterContent {
        if try await runtime.invoke(Bool.self, "__paperback.hasChapter", [chapter.id]) == false {
            _ = try await details(of: series)
        }
        let content = try await runtime.invoke(Content.self, "__paperback.pages", [chapter.id])
        if let html = content.html { return .html(html) }
        return .pages((content.pages ?? []).compactMap { page in
            guard let url = URL(lenient: page.url) else { return nil }
            var request = URLRequest(url: url)
            for (key, value) in page.headers { request.setValue(value, forHTTPHeaderField: key) }
            return request
        })
    }

    public func imageRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        let headers: [String: String] = lock.withLock { coverHeaders } ?? [:]
        for (key, value) in headers where key != "cookie" { request.setValue(value, forHTTPHeaderField: key) }
        return request
    }

    // MARK: Native functions

    private static func installNatives(_ runtime: JSRuntime, state: PaperbackState, userAgent: String) {
        let agent: @convention(block) () -> String = { userAgent }
        let get: @convention(block) (String, Bool) -> Any = { key, secure in state.get(key, secure: secure) ?? NSNull() }
        let set: @convention(block) (String, JSValue, Bool) -> Void = { key, value, secure in
            state.set(key, value: value.isNull || value.isUndefined ? nil : value.toString(), secure: secure)
        }
        let reset: @convention(block) () -> Void = { state.reset() }
        let encode: @convention(block) (JSValue) -> String = { [weak runtime] value in runtime?.bytes(of: value).base64EncodedString() ?? "" }
        let decode: @convention(block) (String) -> Any = { [weak runtime] text in
            var clean = text.filter { !$0.isWhitespace }.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while clean.count % 4 != 0 { clean += "=" }
            guard let data = Data(base64Encoded: clean) else { return NSNull() }
            // A text comes back as a string, and other bytes as an ArrayBuffer, as the Paperback app does.
            if let text = String(data: data, encoding: .utf8) { return text }
            return runtime?.makeArrayBuffer(data) ?? NSNull()
        }
        let digest: @convention(block) (String, JSValue, Bool) -> Any = { [weak runtime] name, value, hex in
            guard let runtime else { return NSNull() }
            let data = runtime.bytes(of: value)
            let bytes: [UInt8] = switch name.uppercased() {
            case "MD5": Array(Insecure.MD5.hash(data: data))
            case "SHA-1": Array(Insecure.SHA1.hash(data: data))
            case "SHA-384": Array(SHA384.hash(data: data))
            case "SHA-512": Array(SHA512.hash(data: data))
            default: Array(SHA256.hash(data: data))
            }
            if hex { return bytes.map { String(format: "%02x", $0) }.joined() }
            return runtime.makeArrayBuffer(Data(bytes)) ?? NSNull()
        }
        let aes: @convention(block) (String, Bool, JSValue, JSValue, JSValue, JSValue) -> Any = { [weak runtime] name, encrypt, key, iv, data, extra in
            guard let runtime else { return NSNull() }
            let result = PaperbackCrypto.aes(
                name, encrypt: encrypt, key: runtime.bytes(of: key), iv: runtime.bytes(of: iv), data: runtime.bytes(of: data),
                additional: extra.isNull || extra.isUndefined ? nil : runtime.bytes(of: extra)
            )
            return result.flatMap { runtime.makeArrayBuffer($0) } ?? NSNull()
        }
        let entities: @convention(block) (String) -> String = { text in (try? Entities.unescape(text)) ?? text }
        let random: @convention(block) (Int) -> Any = { [weak runtime] count in
            runtime?.makeArrayBuffer(Data((0..<max(count, 0)).map { _ in UInt8.random(in: 0...255) })) ?? NSNull()
        }
        let uuid: @convention(block) () -> String = { UUID().uuidString.lowercased() }
        for (name, block) in [("userAgent", agent), ("stateGet", get), ("stateSet", set), ("stateReset", reset), ("base64Encode", encode),
                              ("base64Decode", decode), ("digest", digest), ("aes", aes), ("decodeEntities", entities), ("random", random), ("uuid", uuid)] as [(String, Any)] {
            runtime.define(name, block)
        }
        runtime.defineAsync("webView") { try await PaperbackWebView.run($0) }
    }
}

/// The state of one extension, as JSON text for each key. It stays in a file next to the code of the extension.
final class PaperbackState: @unchecked Sendable {
    private struct Stored: Codable { var plain: [String: String] = [:]; var secure: [String: String] = [:] }
    private var stored: Stored
    private let file: URL?
    private let lock = NSLock()

    init(file: URL?) {
        self.file = file
        stored = file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
    }

    func get(_ key: String, secure: Bool) -> String? {
        lock.withLock { secure ? stored.secure[key] : stored.plain[key] }
    }

    func set(_ key: String, value: String?, secure: Bool) {
        lock.withLock {
            if secure { stored.secure[key] = value } else { stored.plain[key] = value }
            write()
        }
    }

    func reset() {
        lock.withLock {
            stored.plain = [:]
            write()
        }
    }

    private func write() {
        guard let file, let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: file, options: .atomic)
    }
}

/// AES-CBC with PKCS#7 padding, and AES-GCM with a tag of 16 bytes at the end of the data, as in Web Crypto.
enum PaperbackCrypto {
    static func aes(_ name: String, encrypt: Bool, key: Data, iv: Data, data: Data, additional: Data?) -> Data? {
        switch name {
        case "AES-GCM":
            let symmetric = SymmetricKey(data: key)
            guard let nonce = try? AES.GCM.Nonce(data: iv) else { return nil }
            if encrypt {
                guard let box = try? (additional.map { try AES.GCM.seal(data, using: symmetric, nonce: nonce, authenticating: $0) } ?? AES.GCM.seal(data, using: symmetric, nonce: nonce)) else { return nil }
                return box.ciphertext + box.tag
            }
            guard data.count >= 16, let box = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: data.dropLast(16), tag: data.suffix(16)) else { return nil }
            return try? (additional.map { try AES.GCM.open(box, using: symmetric, authenticating: $0) } ?? AES.GCM.open(box, using: symmetric))
        case "AES-CBC":
            var output = Data(count: data.count + kCCBlockSizeAES128)
            var moved = 0
            let outputCount = output.count
            let status = output.withUnsafeMutableBytes { out in
                data.withUnsafeBytes { input in
                    key.withUnsafeBytes { keyBytes in
                        iv.withUnsafeBytes { ivBytes in
                            CCCrypt(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                    keyBytes.baseAddress, key.count, ivBytes.baseAddress, input.baseAddress, data.count,
                                    out.baseAddress, outputCount, &moved)
                        }
                    }
                }
            }
            guard status == kCCSuccess else { return nil }
            return output.prefix(moved)
        default:
            return nil
        }
    }
}
