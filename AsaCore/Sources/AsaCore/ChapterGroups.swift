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

    private static let numberPattern = try! NSRegularExpression(pattern: #"(?i)(?:ch(?:apter|\.)?|episode|ep\.?|#)\s*(\d+(?:\.\d+)?)"#)
    private static let anyNumber = try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)"#)

    /// The number of a chapter in its title, such as 12 in "Vol. 2 Ch. 12: The Sea" or 7.5 in "Chapter 7.5".
    /// With no word such as "Ch.", the last number of the title counts.
    public static func number(of title: String) -> Double? {
        let range = NSRange(title.startIndex..., in: title)
        if let match = numberPattern.firstMatch(in: title, range: range), let found = Range(match.range(at: 1), in: title) {
            return Double(title[found])
        }
        // A volume number is not the chapter number.
        let withoutVolume = title.replacingOccurrences(of: #"(?i)\b(?:vol(?:ume)?\.?|v\.)\s*\d+(?:\.\d+)?"#, with: "", options: .regularExpression)
        let rest = NSRange(withoutVolume.startIndex..., in: withoutVolume)
        guard let last = anyNumber.matches(in: withoutVolume, range: rest).last, let found = Range(last.range(at: 1), in: withoutVolume) else { return nil }
        return Double(withoutVolume[found])
    }

    /// The place in a new list of chapters of the chapter that the user reads in an old list:
    /// the chapter with the same number, or else the same part of the list.
    public static func place(of index: Int, from old: [String], in new: [String]) -> Int {
        guard !new.isEmpty else { return 0 }
        if old.indices.contains(index), let number = number(of: old[index]),
           let match = new.firstIndex(where: { Self.number(of: $0) == number }) {
            return match
        }
        guard old.count > 1 else { return 0 }
        return min(Int((Double(index) / Double(old.count - 1) * Double(new.count - 1)).rounded()), new.count - 1)
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
