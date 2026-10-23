import Foundation

/// The pairs of pages of a reader on a wide screen.
public enum Spreads {
    /// The pages of each spread, in the order of the book. The first page is alone, as the cover of a book is.
    /// A wide page, such as a page of two pages in one image, is alone. With `shift`, each pair moves by one page,
    /// for a book where the scan puts the pairs on the other pages.
    public static func make(count: Int, wide: (Int) -> Bool, shift: Bool) -> [[Int]] {
        guard count > 0 else { return [] }
        var spreads: [[Int]] = []
        var index = 0
        if !shift {
            spreads.append([0])
            index = 1
        }
        while index < count {
            if wide(index) || index + 1 >= count || wide(index + 1) {
                spreads.append([index])
                index += 1
            } else {
                spreads.append([index, index + 1])
                index += 2
            }
        }
        return spreads
    }

    /// The spread that has the page. A page out of the book gives the nearest spread.
    public static func index(of page: Int, in spreads: [[Int]]) -> Int {
        if let found = spreads.firstIndex(where: { $0.contains(page) }) { return found }
        return page < 0 ? 0 : max(spreads.count - 1, 0)
    }
}
