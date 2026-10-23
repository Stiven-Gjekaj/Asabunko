import CryptoKit
import Foundation

/// The settings of an Aidoku source as a form: groups, pages, choices, lists, buttons, links, steppers, and
/// sign-ins. The settings come from settings.json and from `get_settings`. The values stay in the defaults of
/// the source, with the keys that the sources of aidoku-rs read.
final class AidokuSettings: @unchecked Sendable {
    /// The settings, as the dictionaries of settings.json. A setting of `get_settings` has the same keys.
    private let items: [[String: Any]]
    /// Each setting by the ID of its row.
    private let byID: [String: [String: Any]]
    private let defaults: AidokuDefaults

    var isEmpty: Bool { items.isEmpty }

    /// `languages` are the languages of the source. A source of more than one language gets a choice of them.
    init(json: Data?, dynamic: Data?, defaults: AidokuDefaults, languages: [String], multiLanguage: Bool) {
        var items = json.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
        if let dynamic {
            var r = PostcardReader(dynamic)
            if let more = try? r.list({ try Self.readSetting(&$0) }) { items += more }
        }
        if languages.count > 1 {
            let names = languages.map { Locale.current.localizedString(forIdentifier: $0) ?? $0 }
            let choice: [String: Any] = ["type": multiLanguage ? "multi-select" : "select", "key": "languages", "title": "Languages",
                                         "values": languages, "titles": names]
            items.insert(["type": "group", "title": "Languages", "items": [choice]], at: 0)
        }
        self.items = items
        self.defaults = defaults
        var byID: [String: [String: Any]] = [:]
        func visit(_ item: [String: Any]) {
            byID[Self.id(of: item)] = item
            for child in item["items"] as? [[String: Any]] ?? [] { visit(child) }
        }
        items.forEach(visit)
        self.byID = byID
        // A setting of get_settings has its default only here.
        for item in byID.values where defaults[Self.key(item)] == nil {
            if let value = Self.encodeDefault(item) { defaults[Self.key(item)] = value }
        }
    }

    private static func key(_ item: [String: Any]) -> String { item["key"] as? String ?? "" }

    /// The ID of the row of a setting: its key, or its type and its title for a setting with no key.
    private static func id(of item: [String: Any]) -> String {
        let key = key(item)
        return key.isEmpty ? "\(item["type"] as? String ?? ""):\(item["title"] as? String ?? "")" : key
    }

    private static func encodeDefault(_ item: [String: Any]) -> Data? {
        guard let value = item["default"] else { return nil }
        var w = PostcardWriter()
        switch (item["type"] as? String, value) {
        case let ("switch", flag as Bool): w.bool(flag)
        case let ("segment", number as Int): w.signed(number)
        case let ("stepper", number as Double): w.f32(Float(number))
        case let (_, text as String): w.string(text)
        case let (_, list as [String]): w.list(list) { $0.string($1) }
        default: return nil
        }
        return w.data
    }

    // MARK: The values

    private func read<T>(_ key: String, _ read: (inout PostcardReader) throws -> T) -> T? {
        guard let data = defaults[key] else { return nil }
        var r = PostcardReader(data)
        return try? read(&r)
    }

    private func write(_ key: String, _ write: (inout PostcardWriter) -> Void) {
        var w = PostcardWriter()
        write(&w)
        defaults[key] = w.data
    }

    private func string(_ key: String) -> String? { read(key) { try $0.string() } }
    private func strings(_ key: String) -> [String]? { read(key) { try $0.list { try $0.string() } } }

    /// True when the setting of the key is on: a switch that is on, a sign-in that is done, or a text that is not empty.
    private func isOn(_ key: String) -> Bool {
        switch byID[key]?["type"] as? String {
        case "switch": read(key) { try $0.bool() } ?? false
        case "login": !(string(key) ?? "").isEmpty
        default: read(key) { try $0.bool() } ?? !(string(key) ?? "").isEmpty
        }
    }

    private func isShown(_ item: [String: Any]) -> Bool {
        if let key = item["requires"] as? String, !isOn(key) { return false }
        if let key = item["requiresFalse"] as? String, isOn(key) { return false }
        return true
    }

    /// The values of a choice and their titles. A segment keeps the index of its choice.
    private func choices(_ item: [String: Any]) -> [(value: String, title: String)] {
        if item["type"] as? String == "segment" {
            return (item["options"] as? [String] ?? []).enumerated().map { (String($0), $1) }
        }
        let values = item["values"] as? [String] ?? []
        let titles = item["titles"] as? [String]
        return values.enumerated().map { ($1, titles?[safe: $0] ?? $1) }
    }

    private func chosen(_ item: [String: Any]) -> String? {
        let key = Self.key(item)
        switch item["type"] as? String {
        case "segment": return read(key) { try $0.signed() }.map { String($0) } ?? String(item["default"] as? Int ?? 0)
        case _ where key == "languages": return strings(key)?.first
        default: return string(key) ?? item["default"] as? String ?? choices(item).first?.value
        }
    }

    private func list(_ item: [String: Any]) -> [String] {
        strings(Self.key(item)) ?? item["default"] as? [String] ?? []
    }

    // MARK: The form

    func form(_ id: String) throws -> SourceForm {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard let kind = parts.first else { throw SourceFormError.unknownRow }
        let key = parts.count > 1 ? parts[1] : ""
        switch kind {
        case "root":
            return SourceForm(id: id, sections: sections(items))
        case "page":
            guard let page = byID[key] else { throw SourceFormError.unknownRow }
            return SourceForm(id: id, sections: sections(page["items"] as? [[String: Any]] ?? []))
        case "select", "multi":
            guard let item = byID[key] else { throw SourceFormError.unknownRow }
            let picked: Set<String> = kind == "multi" ? Set(list(item)) : Set([chosen(item)].compactMap { $0 })
            let rows = choices(item).map { choice in
                SourceForm.Row(id: choice.value, type: "labelRow", title: choice.title,
                               mark: picked.contains(choice.value) ? "included" : nil, selectable: true)
            }
            return SourceForm(id: id, sections: [SourceForm.Section(id: "choices", rows: rows)])
        case "list":
            guard let item = byID[key] else { throw SourceFormError.unknownRow }
            let entries = list(item).enumerated().map { index, entry in
                SourceForm.Row(id: "entry:\(index)", type: "buttonRow", title: entry)
            }
            let add = SourceForm.Row(id: "add", type: "inputRow", title: item["placeholder"] as? String ?? "Add")
            return SourceForm(id: id, sections: [
                SourceForm.Section(id: "entries", footer: entries.isEmpty ? nil : "Tap an entry to remove it.", rows: entries),
                SourceForm.Section(id: "add", rows: [add]),
            ])
        default:
            throw SourceFormError.unknownRow
        }
    }

    /// The settings of a list in sections. A group is a section. The settings out of a group share a section.
    private func sections(_ list: [[String: Any]]) -> [SourceForm.Section] {
        var result: [SourceForm.Section] = []
        var loose: [SourceForm.Row] = []
        func flush() {
            if !loose.isEmpty { result.append(SourceForm.Section(id: "loose-\(result.count)", rows: loose)) }
            loose = []
        }
        for item in list {
            if item["type"] as? String == "group" {
                guard isShown(item) else { continue }
                flush()
                let rows = rows(item["items"] as? [[String: Any]] ?? [])
                let title = (item["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let footer = item["footer"] as? String
                if !rows.isEmpty || footer != nil {
                    result.append(SourceForm.Section(id: "group-\(result.count)", header: title, footer: footer, rows: rows))
                }
            } else if let row = row(item) {
                loose.append(row)
            }
        }
        flush()
        return result
    }

    /// The rows of a group. A group in a group gives its rows to the outer group.
    private func rows(_ list: [[String: Any]]) -> [SourceForm.Row] {
        list.flatMap { item -> [SourceForm.Row] in
            if item["type"] as? String == "group" { return isShown(item) ? rows(item["items"] as? [[String: Any]] ?? []) : [] }
            return row(item).map { [$0] } ?? []
        }
    }

    private func row(_ item: [String: Any]) -> SourceForm.Row? {
        guard isShown(item) else { return nil }
        let key = Self.key(item), id = Self.id(of: item)
        let title = item["title"] as? String ?? key
        switch item["type"] as? String {
        case "switch":
            return SourceForm.Row(id: id, type: "toggleRow", title: title, subtitle: item["subtitle"] as? String,
                                  on: read(key) { try $0.bool() } ?? item["default"] as? Bool ?? false)
        case "select", "picker", "segment":
            let current = chosen(item)
            let label = choices(item).first { $0.value == current }?.title ?? current
            return SourceForm.Row(id: id, type: "navigationRow", title: title, value: label, form: "select:" + id)
        case "multi-select":
            let picked = Set(list(item))
            let names = choices(item).filter { picked.contains($0.value) }.map(\.title)
            return SourceForm.Row(id: id, type: "navigationRow", title: title, value: names.isEmpty ? "None" : names.joined(separator: ", "),
                                  form: "multi:" + id)
        case "text":
            return SourceForm.Row(id: id, type: "inputRow", title: title, value: string(key) ?? item["default"] as? String ?? "",
                                  secure: item["secure"] as? Bool)
        case "stepper":
            let minimum = (item["minimumValue"] as? NSNumber)?.doubleValue ?? 0
            let value = read(key) { try $0.f32() }.map(Double.init) ?? (item["default"] as? NSNumber)?.doubleValue ?? minimum
            return SourceForm.Row(id: id, type: "stepperRow", title: title, number: value, minimum: minimum,
                                  maximum: (item["maximumValue"] as? NSNumber)?.doubleValue, step: (item["stepValue"] as? NSNumber)?.doubleValue)
        case "button":
            return SourceForm.Row(id: id, type: "buttonRow", title: title,
                                  confirm: item["confirmText"] as? String ?? item["confirmMessage"] as? String, destructive: item["destructive"] as? Bool)
        case "link":
            return SourceForm.Row(id: id, type: "linkRow", title: title, url: item["url"] as? String)
        case "page":
            return SourceForm.Row(id: id, type: "navigationRow", title: title, form: "page:" + id)
        case "editable-list":
            let count = list(item).count
            return SourceForm.Row(id: id, type: "navigationRow", title: title, value: count == 0 ? "None" : String(count), form: "list:" + id)
        case "login":
            return loginRow(item, id: id, title: title)
        default:
            return nil
        }
    }

    private func loginRow(_ item: [String: Any], id: String, title: String) -> SourceForm.Row {
        let key = Self.key(item)
        let signedIn = !(string(key) ?? "").isEmpty
        let method = item["method"] as? String ?? "basic"
        var url = item["url"] as? String ?? (item["urlKey"] as? String).flatMap { string($0) }
        if method == "oauth", !signedIn, item["pkce"] as? Bool == true, let text = url, var parts = URLComponents(string: text) {
            // The code verifier stays until the sign-in ends, so the challenge of the page matches it.
            let verifier = string(key + ".codeVerifier") ?? Self.codeVerifier()
            write(key + ".codeVerifier") { $0.string(verifier) }
            parts.queryItems = (parts.queryItems ?? []) + [
                URLQueryItem(name: "code_challenge", value: Self.challenge(verifier)),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "response_type", value: "code"),
            ]
            url = parts.url?.absoluteString
        }
        let login = SourceForm.Login(method: method, url: url, callbackScheme: item["callbackScheme"] as? String ?? "aidoku",
                                     useEmail: item["useEmail"] as? Bool, signedIn: signedIn, username: string(key + ".username"),
                                     clearsCookies: item["clearCookiesOnLogOut"] as? Bool, storageKeys: item["localStorageKeys"] as? [String])
        return SourceForm.Row(id: id, type: "loginRow", title: signedIn ? item["logoutTitle"] as? String ?? "Sign out" : title,
                              subtitle: signedIn ? string(key + ".username") : nil, login: login)
    }

    private static func codeVerifier() -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<64).map { _ in characters.randomElement()! })
    }

    static func challenge(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// The request that changes the code of an OAuth sign-in with PKCE into a token. Nil for other sign-ins.
    func tokenRequest(row: String, callback: URL) -> URLRequest? {
        guard let item = byID[row], item["pkce"] as? Bool == true, let token = (item["tokenUrl"] as? String).flatMap(URL.init(string:)),
              let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value,
              let verifier = string(Self.key(item) + ".codeVerifier")
        else { return nil }
        let query = (item["url"] as? String).flatMap { URLComponents(string: $0)?.queryItems } ?? []
        var parameters = ["grant_type": "authorization_code", "code": code, "code_verifier": verifier]
        for name in ["redirect_uri", "client_id"] {
            if let value = query.first(where: { $0.name == name })?.value { parameters[name] = value }
        }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        var request = URLRequest(url: token)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(parameters.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&").utf8)
        return request
    }

    // MARK: The actions

    /// Does the action of a row. It runs on the queue of the source, because a sign-in and a notification call the source.
    /// `token` is the answer of the token request of an OAuth sign-in. With no host, the source gets no calls.
    func act(form: String, row: String, input: FormInput, token: String?, host: AidokuHost?) throws {
        let parts = form.split(separator: ":", maxSplits: 1).map(String.init)
        let kind = parts.first ?? ""
        if kind == "select" || kind == "multi" || kind == "list" {
            guard parts.count > 1, let item = byID[parts[1]] else { throw SourceFormError.unknownRow }
            let key = Self.key(item)
            switch (kind, input) {
            case ("select", .tap):
                guard choices(item).contains(where: { $0.value == row }) else { throw SourceFormError.unknownRow }
                if item["type"] as? String == "segment" {
                    write(key) { $0.signed(Int(row) ?? 0) }
                } else if key == "languages" {
                    write(key) { $0.list([row]) { $0.string($1) } }
                } else {
                    write(key) { $0.string(row) }
                }
            case ("multi", .tap):
                var picked = list(item)
                if let index = picked.firstIndex(of: row) { picked.remove(at: index) } else { picked.append(row) }
                // The choices keep the order of the list of the source.
                let order = choices(item).map(\.value)
                picked.sort { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
                write(key) { $0.list(picked) { $0.string($1) } }
            case let ("list", .text(text)) where row == "add":
                let entry = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !entry.isEmpty else { return }
                write(key) { $0.list(list(item) + [entry]) { $0.string($1) } }
            case ("list", .tap):
                guard let index = Int(row.dropFirst("entry:".count)) else { throw SourceFormError.unknownRow }
                var entries = list(item)
                guard entries.indices.contains(index) else { throw SourceFormError.unknownRow }
                entries.remove(at: index)
                write(key) { $0.list(entries) { $0.string($1) } }
            default:
                throw SourceFormError.unknownRow
            }
            try notify(item, host: host)
            return
        }

        guard let item = byID[row] else { throw SourceFormError.unknownRow }
        let key = Self.key(item)
        func text(_ value: String) -> Data { var w = PostcardWriter(); w.string(value); return w.data }
        switch (item["type"] as? String, input) {
        case let ("switch", .toggle(on)):
            write(key) { $0.bool(on) }
        case let ("text", .text(value)):
            write(key) { $0.string(value) }
        case let ("stepper", .number(value)):
            var number = value
            if let low = (item["minimumValue"] as? NSNumber)?.doubleValue { number = max(number, low) }
            if let high = (item["maximumValue"] as? NSNumber)?.doubleValue { number = min(number, high) }
            write(key) { $0.f32(Float(number)) }
        case ("button", .tap):
            break
        case let ("login", .login(username, password)):
            write(key + ".username") { $0.string(username) }
            write(key + ".password") { $0.string(password) }
            write(key) { $0.string("logged_in") }
            if let host, host.exports.contains("handle_basic_login") {
                var r = PostcardReader(try host.call("handle_basic_login", [text(key), text(username), text(password)]))
                guard (try? r.bool()) == true else {
                    signOut(item)
                    throw SourceFormError.refused
                }
            }
        case let ("login", .web(cookies, storage)):
            let names = cookies.keys.sorted()
            write(key + ".keys") { $0.list(names) { $0.string($1) } }
            write(key + ".values") { $0.list(names.map { cookies[$0] ?? "" }) { $0.string($1) } }
            for (name, value) in storage { write(key + ".ls." + name) { $0.string(value) } }
            write(key) { $0.string("logged_in") }
            if let host, host.exports.contains("handle_web_login") {
                var w1 = PostcardWriter(), w2 = PostcardWriter()
                w1.list(names) { $0.string($1) }
                w2.list(names.map { cookies[$0] ?? "" }) { $0.string($1) }
                var r = PostcardReader(try host.call("handle_web_login", [text(key), w1.data, w2.data]))
                guard (try? r.bool()) == true else {
                    signOut(item)
                    throw SourceFormError.refused
                }
            }
        case let ("login", .callback(url)):
            write(key) { $0.string(token ?? url.absoluteString) }
        case ("login", .logout):
            signOut(item)
        default:
            throw SourceFormError.unknownRow
        }
        try notify(item, host: host)
    }

    private func signOut(_ item: [String: Any]) {
        let key = Self.key(item)
        for suffix in ["", ".username", ".password", ".keys", ".values", ".codeVerifier"] { defaults[key + suffix] = nil }
        for name in item["localStorageKeys"] as? [String] ?? [] { defaults[key + ".ls." + name] = nil }
    }

    /// Tells the source that a setting changed, when the setting asks for it.
    private func notify(_ item: [String: Any], host: AidokuHost?) throws {
        guard let notification = item["notification"] as? String, let host, host.exports.contains("handle_notification") else { return }
        var w = PostcardWriter()
        w.string(notification)
        try host.callWithNoResult("handle_notification", [w.data])
    }

    // MARK: The settings of get_settings

    /// One `Setting` of aidoku-rs in postcard, as a dictionary with the keys of settings.json.
    static func readSetting(_ r: inout PostcardReader) throws -> [String: Any] {
        var item: [String: Any] = [:]
        func strings(_ r: inout PostcardReader) throws -> [String] { try r.list { try $0.string() } }
        item["type"] = try r.string()
        item["key"] = try r.string()
        item["title"] = try r.string()
        item["notification"] = try r.option { try $0.string() }
        item["requires"] = try r.option { try $0.string() }
        item["requiresFalse"] = try r.option { try $0.string() }
        item["refreshes"] = try r.option { try strings(&$0) }
        switch try r.unsigned() {
        case 0:
            item["footer"] = try r.option { try $0.string() }
            item["items"] = try r.list { try readSetting(&$0) }
        case 1, 12:
            item["values"] = try strings(&r)
            item["titles"] = try r.option { try strings(&$0) }
            if item["type"] as? String != "picker" { _ = try r.option { try $0.bool() } }
            item["default"] = try r.option { try $0.string() }
        case 2:
            item["values"] = try strings(&r)
            item["titles"] = try r.option { try strings(&$0) }
            _ = try r.option { try $0.bool() }
            item["default"] = try r.option { try strings(&$0) }
        case 3:
            item["subtitle"] = try r.option { try $0.string() }
            _ = try r.option { try $0.bool() }
            item["default"] = try r.bool()
        case 4:
            item["minimumValue"] = try r.f64()
            item["maximumValue"] = try r.f64()
            item["stepValue"] = try r.option { try $0.f64() }
            item["default"] = try r.option { try $0.f64() }
        case 5:
            item["options"] = try strings(&r)
            item["default"] = try r.option { Int(try $0.signed()) }
        case 6:
            item["placeholder"] = try r.option { try $0.string() }
            _ = try r.option { try $0.signed() }
            item["autocorrectionDisabled"] = try r.option { try $0.bool() }
            _ = try r.option { try $0.signed() }
            _ = try r.option { try $0.signed() }
            item["secure"] = try r.option { try $0.bool() }
            item["default"] = try r.option { try $0.string() }
        case 7:
            break
        case 8:
            item["url"] = try r.string()
            item["external"] = try r.option { try $0.bool() }
        case 9:
            item["method"] = try r.string()
            item["url"] = try r.option { try $0.string() }
            item["urlKey"] = try r.option { try $0.string() }
            item["logoutTitle"] = try r.option { try $0.string() }
            item["pkce"] = try r.bool()
            item["tokenUrl"] = try r.option { try $0.string() }
            item["callbackScheme"] = try r.option { try $0.string() }
            item["useEmail"] = try r.bool()
            item["localStorageKeys"] = try r.option { try strings(&$0) }
            item["clearCookiesOnLogOut"] = try r.bool()
        case 10:
            item["items"] = try r.list { try readSetting(&$0) }
            _ = try r.option { try $0.bool() }
            _ = try r.option { try $0.bool() }
            _ = try r.option { r -> Bool in
                if try r.string() == "system" {
                    _ = try r.string(); _ = try r.string(); _ = try r.option { try $0.signed() }
                } else {
                    _ = try r.string()
                }
                return true
            }
            item["info"] = try r.option { try $0.string() }
        case 11:
            item["lineLimit"] = try r.option { Int(try $0.signed()) }
            item["inline"] = try r.bool()
            item["placeholder"] = try r.option { try $0.string() }
            item["default"] = try r.option { try strings(&$0) }
        case let tag:
            throw PostcardError.badTag(UInt64(tag))
        }
        return item.compactMapValues { $0 }
    }
}
