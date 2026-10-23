import Foundation
import Testing
@testable import AsaCore

@Suite struct PostcardTests {
    @Test func writesTheBytesOfPostcard() {
        var writer = PostcardWriter()
        writer.varint(300)          // AC 02
        writer.signed(-1)           // 01
        writer.signed(1)            // 02
        writer.string("asa")        // 03 61 73 61
        writer.option(nil as String?) { $0.string($1) }  // 00
        writer.option(7) { $0.unsigned($1) }             // 01 07
        writer.f32(1.5)             // 00 00 C0 3F
        writer.list([true, false]) { $0.bool($1) }       // 02 01 00
        #expect(Array(writer.data) == [0xAC, 0x02, 0x01, 0x02, 0x03, 0x61, 0x73, 0x61, 0x00, 0x01, 0x07, 0x00, 0x00, 0xC0, 0x3F, 0x02, 0x01, 0x00])
    }

    @Test func readsWhatItWrites() throws {
        var writer = PostcardWriter()
        writer.signed(Int64.min)
        writer.signed(-123_456)
        writer.f64(-2.25)
        writer.string("朝の文庫")
        writer.list(["a", "bc"]) { $0.string($1) }
        var reader = PostcardReader(writer.data)
        #expect(try reader.signed() == Int64.min)
        #expect(try reader.signed() == -123_456)
        #expect(try reader.f64() == -2.25)
        #expect(try reader.string() == "朝の文庫")
        #expect(try reader.list { try $0.string() } == ["a", "bc"])
        #expect(reader.isAtEnd)
    }

    @Test func failsAtTheEndOfTheData() {
        var reader = PostcardReader(Data([0x05, 0x61]))
        #expect(throws: PostcardError.end) { try reader.string() }
    }
}
