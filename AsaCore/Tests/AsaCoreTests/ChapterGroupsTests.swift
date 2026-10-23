import Foundation
import Testing
@testable import AsaCore

@Suite struct ChapterGroupsTests {
    @Test func findsTheVolumeInTheFormsOfTheSources() {
        #expect(ChapterGroups.volume(of: "Vol. 2 Ch. 10") == "2")
        #expect(ChapterGroups.volume(of: "Volume 03: The Sea") == "3")
        #expect(ChapterGroups.volume(of: "vol 1.5 extra") == "1.5")
        #expect(ChapterGroups.volume(of: "V.4 Chapter 2") == "4")
        #expect(ChapterGroups.volume(of: "Chapter 12: Revolution") == nil)
        #expect(ChapterGroups.volume(of: "Chapter 7") == nil)
    }

    @Test func groupsTheChaptersByVolumeInTheirOrder() {
        let titles = ["Vol. 1 Ch. 1", "Vol. 1 Ch. 2", "Vol. 2 Ch. 3", "Ch. 4", "Vol. 2 Ch. 5"]
        let volumes = ChapterGroups.volumes(titles)
        #expect(volumes?.map(\.name) == ["Volume 1", "Volume 2", "No volume"])
        #expect(volumes?.map(\.chapters) == [[0, 1], [2, 4], [3]])
    }

    @Test func givesNoVolumesWhenNoTitleHasOne() {
        #expect(ChapterGroups.volumes(["Chapter 1", "Chapter 2"]) == nil)
        #expect(ChapterGroups.volumes([]) == nil)
    }

    @Test func splitsALongListIntoRangesOfFifty() {
        let ranges = ChapterGroups.ranges(count: 120)
        #expect(ranges == [0..<50, 50..<100, 100..<120])
        #expect(ranges.map(ChapterGroups.name) == ["1-50", "51-100", "101-120"])
        #expect(ChapterGroups.ranges(count: 30) == [0..<30])
        #expect(ChapterGroups.ranges(count: 0).isEmpty)
        #expect(ChapterGroups.name(of: 100..<101) == "101")
    }
}
