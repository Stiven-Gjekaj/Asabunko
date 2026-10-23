import Foundation
import Testing
@testable import AsaCore

@Suite struct TitleSearchTests {
    @Test func keyIgnoresCaseAccentsAndMarks() {
        #expect(TitleMatch.key("Café: The Story!") == TitleMatch.key("cafe the story"))
        #expect(TitleMatch.key("One-Punch Man") == "onepunchman")
    }

    @Test func scoreOrdersSameStartAndPart() {
        #expect(TitleMatch.score("Blue Lock", query: "blue lock") == 3)
        #expect(TitleMatch.score("Blue Lock: Episode Nagi", query: "Blue Lock") == 2)
        #expect(TitleMatch.score("The Blue Lock Fan Book", query: "Blue Lock") == 1)
        #expect(TitleMatch.score("Red Lock", query: "Blue Lock") == 0)
        #expect(TitleMatch.score("Anything", query: "  ") == 0)
    }

    @Test func groupsJoinTheSameTitleOfTwoSources() {
        var results = SearchResults(query: "sunrise")
        results.add([OnlineSeries(id: "a1", title: "Sunrise Tale"), OnlineSeries(id: "a2", title: "Sunrise")], from: "A")
        results.add([OnlineSeries(id: "b1", title: "SUNRISE", cover: URL(string: "https://b.test/c.png"))], from: "B")
        let groups = results.sorted
        #expect(groups.map(\.title) == ["Sunrise", "Sunrise Tale"])
        #expect(groups[0].hits.map(\.source) == ["A", "B"])
        #expect(groups[0].cover?.source == "B")
        #expect(groups[1].cover == nil)
    }

    @Test func moreSourcesComeFirstWhenTheScoreIsTheSame() {
        var results = SearchResults(query: "moon")
        results.add([OnlineSeries(id: "1", title: "Moon One"), OnlineSeries(id: "2", title: "Moon Two")], from: "A")
        results.add([OnlineSeries(id: "3", title: "Moon Two")], from: "B")
        #expect(results.sorted.map(\.title) == ["Moon Two", "Moon One"])
    }

    @Test func aSourceCountsOneTimeInAGroup() {
        var results = SearchResults(query: "x")
        results.add([OnlineSeries(id: "1", title: "Same"), OnlineSeries(id: "2", title: "same")], from: "A")
        #expect(results.sorted.first?.hits.count == 1)
        #expect(results.sorted.first?.hits.first?.series.id == "1")
    }

    @Test func theSourceWithMostChaptersWins() {
        #expect(SourceChoice.best([("A", 10), ("B", 42), ("C", 42)]) == "B")
        #expect(SourceChoice.best([("A", nil), ("B", 3)]) == "B")
        #expect(SourceChoice.best([("A", nil), ("B", 0)]) == "A")
        #expect(SourceChoice.best([]) == nil)
    }

    @Test func mixTakesOneOfEachSourceInTurnWithNoSameTitle() {
        let a = [SearchHit(source: "A", series: OnlineSeries(id: "1", title: "One")), SearchHit(source: "A", series: OnlineSeries(id: "2", title: "Two"))]
        let b = [SearchHit(source: "B", series: OnlineSeries(id: "3", title: "one")), SearchHit(source: "B", series: OnlineSeries(id: "4", title: "Four")),
                 SearchHit(source: "B", series: OnlineSeries(id: "5", title: "Five"))]
        #expect(TitleMix.roundRobin([a, b]).map(\.series.id) == ["1", "2", "4", "5"])
        #expect(TitleMix.roundRobin([a, b], limit: 2).map(\.series.id) == ["1", "2"])
        #expect(TitleMix.roundRobin([]).isEmpty)
    }

    @Test func aChapterOfTwoGroupsCountsOneTime() {
        let chapters = [
            OnlineChapter(id: "1a", title: "Ch. 1", number: 1, group: "A"), OnlineChapter(id: "1b", title: "Ch. 1", number: 1, group: "B"),
            OnlineChapter(id: "2", title: "Ch. 2", number: 2), OnlineChapter(id: "x", title: "Extra"), OnlineChapter(id: "y", title: "Extra 2"),
        ]
        #expect(SourceChoice.distinctChapters(chapters) == 4)
        #expect(SourceChoice.distinctChapters([]) == 0)
    }
}
