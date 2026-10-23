import Foundation
import Testing
@testable import AsaCore

@Suite struct MOBIImporterTests {
    @Test func palmDOCReadsLiteralsSpacesAndCopies() {
        // "ab", then a copy of 3 bytes from 2 back ("aba"), then " c" as one byte, then 2 raw bytes.
        let pair = UInt16((2 << 3) | (3 - 3)) | 0x8000
        let compressed = Data([0x61, 0x62, UInt8(pair >> 8), UInt8(pair & 0xFF), 0x63 ^ 0x80, 0x02, 0x00, 0xFF])
        #expect([UInt8](MOBIImporter.palmDOC(compressed)) == [0x61, 0x62, 0x61, 0x62, 0x61, 0x20, 0x63, 0x00, 0xFF])
    }

    @Test func trailingEntriesComeOffTheEnd() {
        // One entry of 3 bytes, with its size in its last byte. Before it, the multibyte mark 0x01
        // tells 1 + 1 bytes: the mark and one byte of the text.
        let record = Data([0x41, 0x42, 0x43]) + Data([0x01]) + Data([0x58, 0x59, 0x83])
        #expect(MOBIImporter.trailingSize(record, flags: 0b11) == 5)
        #expect(MOBIImporter.trailingSize(record, flags: 0b10) == 3)
        #expect(MOBIImporter.trailingSize(record, flags: 0) == 0)
    }

    @Test func fragmentsGoIntoTheirSkeleton() {
        let text = Data("<html><body></body></html><p>One</p><p>Two</p><html><body></body></html><p>Three</p>".utf8)
        let first = "<html><body></body></html>".utf8.count
        let skeletons = [
            MOBIImporter.Skeleton(fragments: 2, start: 0, length: first),
            MOBIImporter.Skeleton(fragments: 1, start: first + 20, length: first),
        ]
        let fragments = [
            MOBIImporter.Fragment(insert: 12, start: 0, length: 10),
            MOBIImporter.Fragment(insert: 22, start: 10, length: 10),
            MOBIImporter.Fragment(insert: first + 20 + 12, start: 0, length: 12),
        ]
        let parts = MOBIImporter.assemble(text, skeletons: skeletons, fragments: fragments).map { String(decoding: $0, as: UTF8.self) }
        #expect(parts == ["<html><body><p>One</p><p>Two</p></body></html>", "<html><body><p>Three</p></body></html>"])
    }

    @Test func indexValuesFollowTheControlByte() {
        // Tag 1 has one value, and tag 6 has two values in each entry. The control byte marks both.
        let tags = [Index.Tag(tag: 1, valuesPerEntry: 1, mask: 0x01, end: false), Index.Tag(tag: 6, valuesPerEntry: 2, mask: 0x02, end: false),
                    Index.Tag(tag: 0, valuesPerEntry: 0, mask: 0, end: true)]
        // 300 is 0x02 0xAC in 7-bit bytes: 0b10 and 0b0101100.
        let values = Index.values([0x83, 0x02, 0xAC, 0x8A], tags: tags, control: [0x03])
        #expect(values[1] == [3])
        #expect(values[6] == [300, 10])
    }

    @Test func kf8LinksPointToTheFiles() {
        var images = MOBIImporter.Resources()
        images.byNumber[11] = "00011.jpg"
        let html = #"<img src="kindle:embed:000B?mime=image/jpeg"/><link href="kindle:flow:0001?mime=text/css"/><a href="kindle:pos:fid:0004:off:0000000000">x</a>"#
        let out = MOBIImporter.links(html, images: images, styles: ["flow0001.css"])
        #expect(out == ##"<img src="../images/00011.jpg"/><link href="../styles/flow0001.css"/><a href="#">x</a>"##)
    }

    @Test func importsAMOBI6BookWithChaptersAnImageAndTheFacts() throws {
        let html = "<html><head></head><body><h1>The Sea</h1><p>Waves came.</p><img recindex=\"00001\"><mbp:pagebreak/><p><font size=\"7\">Part Two</font></p><p>The shore.</p></body></html>"
        let image = Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data(repeating: 0, count: 12)
        let file = try temporaryFolder().appendingPathComponent("sea.mobi")
        try mobiFile(text: Data(html.utf8), images: [image], author: "Mina Ko", title: "The Long Sea").write(to: file)
        let folder = try temporaryFolder().appendingPathComponent("book")
        let novel = try MOBIImporter.importBook(from: file, into: folder)
        #expect(novel.title == "The Long Sea")
        #expect(novel.author == "Mina Ko")
        #expect(novel.chapters.map(\.title) == ["The Sea", "Part Two"])
        let first = String(decoding: try Data(contentsOf: folder.appendingPathComponent(novel.chapters[0].path)), as: UTF8.self)
        #expect(first.contains(#"src="../images/00001.jpg""#))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("images/00001.jpg").path))
    }

    @Test func refusesABookWithDRM() throws {
        let file = try temporaryFolder().appendingPathComponent("locked.azw")
        try mobiFile(text: Data("<p>x</p>".utf8), images: [], author: nil, title: nil, encryption: 2).write(to: file)
        let folder = try temporaryFolder().appendingPathComponent("book")
        #expect(throws: MOBIImporter.Failure.encrypted) { try MOBIImporter.importBook(from: file, into: folder) }
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func refusesAFileThatIsNotMOBI() throws {
        let file = try temporaryFolder().appendingPathComponent("not.mobi")
        try Data(repeating: 0x20, count: 200).write(to: file)
        #expect(throws: MOBIImporter.Failure.notMOBI) { try MOBIImporter.importBook(from: file, into: try temporaryFolder().appendingPathComponent("b")) }
    }

    /// A MOBI 6 file with no compression: record 0, one text record, and the image records.
    private func mobiFile(text: Data, images: [Data], author: String?, title: String?, encryption: UInt16 = 0) -> Data {
        var exth = Data()
        var count: UInt32 = 0
        for (type, value) in [(100, author), (503, title)] {
            guard let value else { continue }
            exth += be32(UInt32(type)) + be32(UInt32(8 + value.utf8.count)) + Data(value.utf8)
            count += 1
        }
        exth = Data("EXTH".utf8) + be32(UInt32(12 + exth.count)) + be32(count) + exth

        var mobi = Data(count: 0xE8)
        func put(_ value: UInt32, at offset: Int) { mobi.replaceSubrange(offset..<(offset + 4), with: be32(value)) }
        mobi.replaceSubrange(0..<4, with: Data("MOBI".utf8))
        put(0xE8, at: 4)
        put(65001, at: 12)
        put(6, at: 20)
        put(images.isEmpty ? 0xFFFF_FFFF : 2, at: 0x5C)
        put(0x40, at: 0x70)
        put(0xFFFF_FFFF, at: 0x44)
        var record0 = be16(1) + be16(0) + be32(UInt32(text.count)) + be16(1) + be16(4096) + be16(encryption) + be16(0)
        record0 += mobi + exth
        // The name of the book is not set, so the title comes from the EXTH header.
        let records = [record0, text] + images
        var offset = 78 + records.count * 8 + 2
        var file = Data(count: 60) + Data("BOOKMOBI".utf8) + Data(count: 8) + be16(UInt16(records.count))
        for record in records {
            file += be32(UInt32(offset)) + Data(count: 4)
            offset += record.count
        }
        file += Data(count: 2)
        for record in records { file += record }
        return file
    }

    private func be32(_ value: UInt32) -> Data { Data([UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]) }
    private func be16(_ value: UInt16) -> Data { Data([UInt8(value >> 8), UInt8(value & 0xFF)]) }
}
