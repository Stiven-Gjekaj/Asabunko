import Foundation
import Testing
@testable import AsaCore

/// A fetcher that answers the GraphQL queries of the test by a word in the query.
private func graphQL(_ answers: [String: String], seen: SeenRequests) -> Fetcher {
    { request in
        seen.add(request)
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        let key = answers.keys.sorted { $0.count > $1.count }.first { body.contains($0) } ?? ""
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        return (Data((answers[key] ?? #"{"errors":[{"message":"unknown query"}]}"#).utf8), response)
    }
}

@Suite struct SuwayomiTests {
    let seen = SeenRequests()

    private func server() -> SuwayomiServer {
        SuwayomiServer(base: URL(string: "http://pc.local:4567/api/graphql/")!, fetcher: graphQL([
            "sources {": #"{"data":{"sources":{"nodes":[{"id":"0","name":"Local source","lang":"localsourcelang"},{"id":"2499283573021220255","name":"MangaDex","displayName":"MangaDex (EN)","lang":"en","iconUrl":"/api/v1/extension/icon/mangadex.apk","isNsfw":true,"supportsLatest":true}]}}}"#,
            "fetchSourceManga": #"{"data":{"fetchSourceManga":{"hasNextPage":true,"mangas":[{"id":7,"title":"Yotsuba&!","thumbnailUrl":"/api/v1/manga/7/thumbnail"}]}}}"#,
            "fetchManga": #"{"data":{"fetchManga":{"manga":{"id":7,"title":"Yotsuba&!","thumbnailUrl":"/api/v1/manga/7/thumbnail","author":"Kiyohiko Azuma","artist":"Kiyohiko Azuma","description":"A girl and her summer.","genre":["Comedy","Slice of Life"],"status":"ONGOING"}},"fetchChapters":{"chapters":[{"id":12,"name":"Chapter 2","chapterNumber":2,"uploadDate":"1790000000000","scanlator":"Group","sourceOrder":0},{"id":11,"name":"Chapter 1","chapterNumber":1,"uploadDate":"1780000000000","scanlator":null,"sourceOrder":1}]}}}"#,
            "fetchChapterPages": #"{"data":{"fetchChapterPages":{"pages":["/api/v1/manga/7/chapter/1/page/0","/api/v1/manga/7/chapter/1/page/1"]}}}"#,
        ], seen: seen))
    }

    private let info = SourceInfo(id: "2499283573021220255", name: "MangaDex (EN)", language: "en", version: "", icon: nil, code: URL(string: "http://pc.local:4567")!, novels: false)

    @Test func listsTheSourcesOfTheServerButNotItsLocalSource() async throws {
        let sources = try await server().sources()
        #expect(sources.map(\.name) == ["MangaDex (EN)"])
        #expect(sources.first?.icon == URL(string: "http://pc.local:4567/api/v1/extension/icon/mangadex.apk"))
        #expect(sources.first?.adult == true)
        #expect(seen.all.first?.url == URL(string: "http://pc.local:4567/api/graphql"))
        #expect(seen.all.first?.httpMethod == "POST")
    }

    @Test func listsSeriesAndReadsTheirChaptersFromTheOldest() async throws {
        let source = SuwayomiSource(info: info, server: server()) { var r = $0; r.setValue("Basic x", forHTTPHeaderField: "Authorization"); return r }
        let page = try await source.popular(page: 1)
        #expect(page == OnlinePage(items: [OnlineSeries(id: "7", title: "Yotsuba&!", cover: URL(string: "http://pc.local:4567/api/v1/manga/7/thumbnail"))], hasMore: true))
        let body = try #require(seen.all.last?.httpBody)
        let variables = try #require((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["variables"] as? [String: Any])
        #expect(variables["source"] as? String == "2499283573021220255")
        #expect(variables["type"] as? String == "POPULAR")

        let details = try await source.details(of: page.items[0])
        #expect(details.author == "Kiyohiko Azuma")
        #expect(details.status == "Ongoing")
        #expect(details.chapters.map(\.id) == ["11", "12"])
        #expect(details.chapters[1].date == "2026-09-21")
        #expect(details.chapters[1].group == "Group")

        guard case let .pages(pages) = try await source.content(of: details.chapters[0], in: details.series) else { Issue.record("no pages"); return }
        #expect(pages.map(\.url) == [URL(string: "http://pc.local:4567/api/v1/manga/7/chapter/1/page/0"), URL(string: "http://pc.local:4567/api/v1/manga/7/chapter/1/page/1")])
        #expect(pages.first?.value(forHTTPHeaderField: "Authorization") == "Basic x")
    }

    @Test func givesTheMessageOfAGraphQLError() async throws {
        let source = SuwayomiSource(info: info, server: SuwayomiServer(base: URL(string: "http://pc.local:4567")!, fetcher: graphQL([:], seen: seen))) { $0 }
        await #expect(throws: SuwayomiServer.Failure.graphQL("unknown query")) { _ = try await source.popular(page: 1) }
    }
}
