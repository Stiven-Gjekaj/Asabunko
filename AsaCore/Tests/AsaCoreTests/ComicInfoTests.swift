import Foundation
import Testing
@testable import AsaCore

@Suite struct ComicInfoTests {
    @Test func readsTheFieldsAndTheDirection() throws {
        let info = try #require(ComicInfo.parse(comicInfo([
            "Series": "Yotsuba&amp;!", "Number": "3", "Title": "Yotsuba and Rain", "Manga": "YesAndRightToLeft", "Writer": "Azuma",
        ])))
        #expect(info.series == "Yotsuba&!")
        #expect(info.writer == "Azuma")
        #expect(info.readingMode == .rightToLeft)
        #expect(info.displayTitle == "Yotsuba&! 3: Yotsuba and Rain")
    }

    @Test func givesNoDirectionWhenTheMangaFieldIsOnlyYes() throws {
        let info = try #require(ComicInfo.parse(comicInfo(["Manga": "Yes"])))
        #expect(info.readingMode == nil)
    }

    @Test func doesNotRepeatATitleThatIsTheSeries() throws {
        let info = try #require(ComicInfo.parse(comicInfo(["Series": "Saga", "Number": "1", "Title": "saga"])))
        #expect(info.displayTitle == "Saga 1")
    }

    @Test func returnsNilForDataThatIsNotXML() {
        #expect(ComicInfo.parse(Data("<ComicInfo><Title>".utf8)) == nil)
    }
}
