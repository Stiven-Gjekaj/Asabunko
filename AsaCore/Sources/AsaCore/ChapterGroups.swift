import Foundation

/// Puts the chapters of a long series into parts: volumes, or ranges such as 1-50.
public enum ChapterGroups {
    /// The chapters of one volume, by their place in the list.
    public struct Volume: Sendable, Equatable, Identifiable {
        public var id: String { name }
        /// "Volume 2", or "No volume" for the chapters with no volume.
        public var name: String
        public var chapters: [Int]
    }

    private static let pattern = try! NSRegularExpression(pattern: #"(?i)\b(?:vol(?:ume)?\.?|v\.)\s*(\d+(?:\.\d+)?)"#)

    /// The number of the volume in a title, such as "2" in "Vol. 2 Ch. 10" or "Volume 2: The Sea".
    public static func volume(of title: String) -> String? {
        let range = NSRange(title.startIndex..., in: title)
        guard let match = pattern.firstMatch(in: title, range: range), let number = Range(match.range(at: 1), in: title) else { return nil }
        let text = String(title[number])
        // "01" and "1" are the same volume.
        if let value = Double(text) { return value == value.rounded() ? String(Int(value)) : String(value) }
        return text
    }

    /// The volumes in the order of their first chapter. Nil when no chapter has a volume,
    /// because then the volumes do not help.
    public static func volumes(_ titles: [String]) -> [Volume]? {
        var order: [String] = []
        var chapters: [String: [Int]] = [:]
        var found = false
        for (index, title) in titles.enumerated() {
            let number = volume(of: title)
            if number != nil { found = true }
            let name = number.map { "Volume \($0)" } ?? "No volume"
            if chapters[name] == nil { order.append(name) }
            chapters[name, default: []].append(index)
        }
        guard found else { return nil }
        return order.map { Volume(name: $0, chapters: chapters[$0]!) }
    }

    /// Ranges of `size` chapters, such as 0..<50 and 50..<100. One range when the list is short.
    public static func ranges(count: Int, size: Int = 50) -> [Range<Int>] {
        guard count > 0, size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map { $0..<min($0 + size, count) }
    }

    /// The name of a range for the user, with the first chapter as 1: "1-50".
    public static func name(of range: Range<Int>) -> String {
        range.count == 1 ? "\(range.lowerBound + 1)" : "\(range.lowerBound + 1)-\(range.upperBound)"
    }
}
