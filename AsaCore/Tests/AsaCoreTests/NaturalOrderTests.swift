import Foundation
import Testing
@testable import AsaCore

@Suite struct NaturalOrderTests {
    @Test func putsTheNumbersInTheirOrder() {
        #expect(NaturalOrder.sorted(["page10.jpg", "page2.jpg", "Page1.jpg"]) == ["Page1.jpg", "page2.jpg", "page10.jpg"])
    }

    @Test func comparesOneFolderAtATime() {
        let paths = ["Ch 10/01.jpg", "Ch 2/10.jpg", "Ch 2/9.jpg", "Ch 2 extra/01.jpg"]
        #expect(NaturalOrder.sorted(paths) == ["Ch 2/9.jpg", "Ch 2/10.jpg", "Ch 2 extra/01.jpg", "Ch 10/01.jpg"])
    }
}
