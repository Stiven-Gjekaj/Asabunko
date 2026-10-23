import Foundation
import Testing
@testable import AsaCore

/// The byte examples of the layouts of aidoku-rs.
@Suite struct AidokuModelTests {
    @Test func writesAChapterAsTheRustCrate() {
        var w = PostcardWriter()
        Aidoku.Chapter(key: "k", chapterNumber: 1.5, dateUploaded: 1_751_374_800).write(&w)
        #expect(Array(w.data) == [0x01, 0x6B, 0x00, 0x01, 0x00, 0x00, 0xC0, 0x3F, 0x00, 0x01, 0xA0, 0xEF, 0x9E, 0x86, 0x0D, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    @Test func readsAPageResult() throws {
        var r = PostcardReader(Data([0x01, 0x01, 0x31, 0x01, 0x41, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x01]))
        let result = try Aidoku.MangaPageResult.read(&r)
        #expect(result.entries == [Aidoku.Manga(key: "1", title: "A")])
        #expect(result.hasNextPage)
    }

    @Test func readsAPageWithAContext() throws {
        var r = PostcardReader(Data([0x00, 0x01, 0x75, 0x01, 0x01, 0x01, 0x61, 0x01, 0x62, 0x00, 0x00, 0x00]))
        #expect(try Aidoku.Page.read(&r) == Aidoku.Page(content: .url("u", ["a": "b"]), thumbnail: nil, hasDescription: false, description: nil))
    }

    @Test func writesAListing() {
        var w = PostcardWriter()
        Aidoku.Listing(id: "i", name: "n", kind: 1).write(&w)
        #expect(Array(w.data) == [0x01, 0x69, 0x01, 0x6E, 0x01])
    }

    @Test func namesAChapter() {
        #expect(Aidoku.Chapter(key: "a", title: "Rain", chapterNumber: 12, volumeNumber: 2).displayTitle == "Vol. 2 Ch. 12: Rain")
        #expect(Aidoku.Chapter(key: "a", chapterNumber: 12.5).displayTitle == "Ch. 12.5")
        #expect(Aidoku.Chapter(key: "a").displayTitle == "a")
    }
}
