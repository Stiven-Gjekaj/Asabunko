import Testing
@testable import AsaCore

@Suite struct SpreadsTests {
    @Test func pairsThePagesAfterTheCover() {
        #expect(Spreads.make(count: 6, wide: { _ in false }, shift: false) == [[0], [1, 2], [3, 4], [5]])
        #expect(Spreads.make(count: 6, wide: { _ in false }, shift: true) == [[0, 1], [2, 3], [4, 5]])
        #expect(Spreads.make(count: 0, wide: { _ in false }, shift: false).isEmpty)
        #expect(Spreads.make(count: 1, wide: { _ in false }, shift: true) == [[0]])
    }

    @Test func keepsAWidePageAlone() {
        // The page 3 is two pages in one image.
        let spreads = Spreads.make(count: 7, wide: { $0 == 3 }, shift: false)
        #expect(spreads == [[0], [1, 2], [3], [4, 5], [6]])
        #expect(Spreads.index(of: 5, in: spreads) == 3)
        #expect(Spreads.index(of: 3, in: spreads) == 2)
        #expect(Spreads.index(of: 99, in: spreads) == 4)
        #expect(Spreads.index(of: -1, in: spreads) == 0)
    }
}
