import Foundation

public enum AppVersion {
    /// True when `candidate` is newer than `current`. A "v" before the numbers is
    /// not a part of the version.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = parts(candidate), b = parts(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func parts(_ version: String) -> [Int] {
        let text = version.hasPrefix("v") ? String(version.dropFirst()) : version
        return text.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
}
