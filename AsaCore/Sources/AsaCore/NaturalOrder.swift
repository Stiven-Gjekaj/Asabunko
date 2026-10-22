import Foundation

/// The order of the pages: "page 2" comes before "page 10".
/// It compares a path one folder at a time, so that a folder of chapter 2 comes
/// before a folder of chapter 10.
public enum NaturalOrder {
    public static func areInIncreasingOrder(_ a: String, _ b: String) -> Bool {
        let left = a.split(separator: "/", omittingEmptySubsequences: true)
        let right = b.split(separator: "/", omittingEmptySubsequences: true)
        for (x, y) in zip(left, right) {
            switch String(x).compare(String(y), options: [.numeric, .caseInsensitive, .widthInsensitive]) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: continue
            }
        }
        if left.count != right.count { return left.count < right.count }
        // Two names that differ only in case keep one order each time.
        return a < b
    }

    public static func sorted(_ paths: [String]) -> [String] {
        paths.sorted(by: areInIncreasingOrder)
    }
}
