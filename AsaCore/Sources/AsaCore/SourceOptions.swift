import Foundation

/// A filter or a setting of a source, in one form for all kinds of source.
public struct SourceOption: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case text(placeholder: String?)
        case toggle
        /// One choice of a list.
        case select([Choice])
        /// Some choices of a list. With `excludable`, the user can also exclude a choice.
        case multi([Choice], excludable: Bool)
        /// The order of the list, with an ascending switch when `canAscend` is true.
        case sort([Choice], canAscend: Bool)
    }

    public struct Choice: Sendable, Equatable, Hashable {
        public var label: String
        public var value: String

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public var id: String
    public var title: String
    public var kind: Kind
    /// The value before the user changes it.
    public var initial: OptionValue
    /// The name of the type in the source, such as "segment", for the code that saves the value.
    public var raw: String

    public init(id: String, title: String, kind: Kind, initial: OptionValue, raw: String = "") {
        self.id = id
        self.title = title
        self.kind = kind
        self.initial = initial
        self.raw = raw
    }
}

/// The value of a filter or a setting.
public enum OptionValue: Sendable, Codable, Equatable, Hashable {
    case text(String)
    case toggle(Bool)
    case select(String)
    case multi(included: [String], excluded: [String])
    case sort(index: Int, ascending: Bool)
}

/// The filters and the settings of an Aidoku package: filters.json and settings.json.
public enum AidokuOptions {
    /// The filters of filters.json that the app can show. A note has no value, so it does not show.
    public static func filters(_ json: Data?) -> [SourceOption] {
        guard let json, let list = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] else { return [] }
        return list.compactMap(filter)
    }

    /// The filters that `get_filters` gives, as postcard `Vec<Filter>`. Each filter turns into the same
    /// dictionary as an item of filters.json, so one function makes the options of both.
    public static func filters(postcard data: Data) -> [SourceOption] {
        var r = PostcardReader(data)
        guard let items = try? r.list({ try readFilter(&$0) }) else { return [] }
        return items.compactMap(filter)
    }

    /// One `Filter` of aidoku-rs: the common fields, then the fields of its type.
    static func readFilter(_ r: inout PostcardReader) throws -> [String: Any] {
        var item: [String: Any] = [:]
        func strings(_ r: inout PostcardReader) throws -> [String] { try r.list { try $0.string() } }
        item["id"] = try r.option { try $0.string() }
        item["title"] = try r.option { try $0.string() }
        item["hideFromHeader"] = try r.option { try $0.bool() }
        let type = try r.string()
        item["type"] = type
        switch type {
        case "text":
            item["placeholder"] = try r.option { try $0.string() }
        case "sort":
            item["canAscend"] = try r.option { try $0.bool() }
            item["options"] = try strings(&r)
            if let start = try r.option({ r -> [String: Any] in ["index": Int(try r.signed()), "ascending": try r.bool()] }) { item["default"] = start }
        case "check":
            item["name"] = try r.option { try $0.string() }
            item["canExclude"] = try r.option { try $0.bool() }
            item["default"] = try r.option { try $0.bool() }
        case "select":
            item["isGenre"] = try r.option { try $0.bool() }
            item["usesTagStyle"] = try r.option { try $0.bool() }
            item["options"] = try strings(&r)
            item["ids"] = try r.option { try strings(&$0) }
            item["default"] = try r.option { try $0.string() }
        case "multi-select":
            item["isGenre"] = try r.option { try $0.bool() }
            item["canExclude"] = try r.option { try $0.bool() }
            item["usesTagStyle"] = try r.option { try $0.bool() }
            item["options"] = try strings(&r)
            item["ids"] = try r.option { try strings(&$0) }
            item["defaultIncluded"] = try r.option { try strings(&$0) }
            item["defaultExcluded"] = try r.option { try strings(&$0) }
        case "note":
            item["text"] = try r.string()
        case "range":
            item["min"] = try r.option { try $0.f32() }
            item["max"] = try r.option { try $0.f32() }
            item["decimal"] = try r.option { try $0.bool() }
        default:
            throw PostcardError.badTag(0)
        }
        return item
    }

    private static func filter(_ item: [String: Any]) -> SourceOption? {
        guard let type = item["type"] as? String else { return nil }
        let title = (item["title"] as? String) ?? (item["name"] as? String) ?? type.capitalized
        // A filter with no id has its title as the id, or else its type.
        let id = (item["id"] as? String) ?? (item["title"] as? String) ?? type
        let options = item["options"] as? [String] ?? []
        let ids = item["ids"] as? [String]
        let choices = options.enumerated().map { SourceOption.Choice(label: $1, value: ids?[safe: $0] ?? $1) }
        switch type {
        case "text":
            return SourceOption(id: id, title: title, kind: .text(placeholder: item["placeholder"] as? String), initial: .text(""), raw: type)
        case "sort":
            let start = item["default"] as? [String: Any]
            return SourceOption(id: id, title: title, kind: .sort(choices, canAscend: item["canAscend"] as? Bool ?? false),
                                initial: .sort(index: start?["index"] as? Int ?? 0, ascending: start?["ascending"] as? Bool ?? false), raw: type)
        case "check":
            let name = (item["name"] as? String) ?? title
            return SourceOption(id: id, title: name, kind: .toggle, initial: .toggle(item["default"] as? Bool ?? false), raw: type)
        case "select":
            guard !choices.isEmpty else { return nil }
            let start = (item["default"] as? String).flatMap { text in choices.first { $0.value == text || $0.label == text } } ?? choices[0]
            return SourceOption(id: id, title: title, kind: .select(choices), initial: .select(start.value), raw: type)
        case "multi-select":
            guard !choices.isEmpty else { return nil }
            return SourceOption(id: id, title: title, kind: .multi(choices, excludable: item["canExclude"] as? Bool ?? false),
                                initial: .multi(included: item["defaultIncluded"] as? [String] ?? [], excluded: item["defaultExcluded"] as? [String] ?? []),
                                raw: type)
        default:
            return nil
        }
    }

    /// The `Vec<FilterValue>` of a search, in postcard. A text with no value does not go.
    public static func encode(_ values: [String: OptionValue], filters: [SourceOption]) -> Data {
        var items: [(SourceOption, OptionValue)] = []
        for filter in filters {
            let value = values[filter.id] ?? filter.initial
            if case let .text(text) = value, text.isEmpty { continue }
            // The meaning of a check with the value 0 is not clear, and a source can read it as "exclude".
            // So a check goes only when the user changed it, as the Aidoku app does.
            if case .toggle = value, value == filter.initial { continue }
            items.append((filter, value))
        }
        var w = PostcardWriter()
        w.list(items) { w, item in
            let (filter, value) = item
            switch value {
            case let .text(text):
                w.unsigned(0); w.string(filter.id); w.string(text)
            case let .sort(index, ascending):
                w.unsigned(1); w.string(filter.id); w.signed(index); w.bool(ascending)
            case let .toggle(on):
                w.unsigned(2); w.string(filter.id); w.signed(on ? 1 : 0)
            case let .select(choice):
                w.unsigned(3); w.string(filter.id); w.string(choice)
            case let .multi(included, excluded):
                w.unsigned(4); w.string(filter.id)
                w.list(included) { $0.string($1) }
                w.list(excluded) { $0.string($1) }
            }
        }
        return w.data
    }

    /// The settings of settings.json that the app can show: switches, choices, segments, and text.
    public static func settings(_ json: Data?) -> [SourceOption] {
        guard let json, let groups = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] else { return [] }
        var result: [SourceOption] = []
        func visit(_ item: [String: Any]) {
            for child in item["items"] as? [[String: Any]] ?? [] { visit(child) }
            guard let type = item["type"] as? String, let key = item["key"] as? String else { return }
            let title = item["title"] as? String ?? key
            let values = item["values"] as? [String] ?? []
            let titles = item["titles"] as? [String]
            let choices = values.enumerated().map { SourceOption.Choice(label: titles?[safe: $0] ?? $1, value: $1) }
            switch type {
            case "switch":
                result.append(SourceOption(id: key, title: title, kind: .toggle, initial: .toggle(item["default"] as? Bool ?? false), raw: type))
            case "select", "picker":
                guard !choices.isEmpty else { return }
                result.append(SourceOption(id: key, title: title, kind: .select(choices), initial: .select(item["default"] as? String ?? choices[0].value), raw: type))
            case "multi-select":
                guard !choices.isEmpty else { return }
                result.append(SourceOption(id: key, title: title, kind: .multi(choices, excludable: false),
                                           initial: .multi(included: item["default"] as? [String] ?? [], excluded: []), raw: type))
            case "segment":
                let options = item["options"] as? [String] ?? []
                guard !options.isEmpty else { return }
                let segments = options.enumerated().map { SourceOption.Choice(label: $1, value: String($0)) }
                result.append(SourceOption(id: key, title: title, kind: .select(segments), initial: .select(String(item["default"] as? Int ?? 0)), raw: type))
            case "text":
                result.append(SourceOption(id: key, title: title, kind: .text(placeholder: item["placeholder"] as? String),
                                           initial: .text(item["default"] as? String ?? ""), raw: type))
            default:
                break
            }
        }
        groups.forEach(visit)
        return result
    }

    /// The value of a setting in the postcard form of the defaults of aidoku-rs.
    public static func encodeSetting(_ value: OptionValue, of setting: SourceOption) -> Data {
        var w = PostcardWriter()
        switch value {
        case let .toggle(on): w.bool(on)
        case let .select(choice) where setting.raw == "segment": w.signed(Int(choice) ?? 0)
        case let .select(choice): w.string(choice)
        case let .text(text): w.string(text)
        case let .multi(included, _): w.list(included) { $0.string($1) }
        case let .sort(index, _): w.signed(index)
        }
        return w.data
    }

    /// The value of a setting from its postcard form, or nil when the bytes do not fit the setting.
    public static func decodeSetting(_ data: Data, of setting: SourceOption) -> OptionValue? {
        var r = PostcardReader(data)
        switch setting.kind {
        case .toggle: return (try? r.bool()).map(OptionValue.toggle)
        case .select where setting.raw == "segment": return (try? r.signed()).map { .select(String($0)) }
        case .select: return (try? r.string()).map(OptionValue.select)
        case .text: return (try? r.string()).map(OptionValue.text)
        case .multi: return (try? r.list { try $0.string() }).map { .multi(included: $0, excluded: []) }
        case .sort: return nil
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
