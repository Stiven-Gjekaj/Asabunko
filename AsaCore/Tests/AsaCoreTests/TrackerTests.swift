import Foundation
import Testing
@testable import AsaCore

/// Keeps the requests that a tracker sends, and gives each one an answer.
private final class FakeSite: @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [URLRequest] = []
    let answer: @Sendable (URLRequest) -> (Int, Any)

    init(answer: @escaping @Sendable (URLRequest) -> (Int, Any)) { self.answer = answer }

    var requests: [URLRequest] { lock.withLock { sent } }

    var fetcher: Fetcher {
        { [self] request in
            lock.withLock { sent.append(request) }
            let (status, body) = answer(request)
            let data = try JSONSerialization.data(withJSONObject: body)
            return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
}

private func body(_ request: URLRequest) -> String { String(decoding: request.httpBody ?? Data(), as: UTF8.self) }

@Suite struct TrackerTests {
    @Test func findsATitleOnAniListWithNoToken() async throws {
        let site = FakeSite { _ in
            (200, ["data": ["Page": ["media": [["id": 7, "chapters": 40, "title": ["userPreferred": "Sunrise"]], ["id": 8, "title": ["userPreferred": "Dusk"]]]]]])
        }
        let tracker = Tracker(kind: .anilist, clientID: "1", token: nil, fetcher: site.fetcher)
        let hits = try await tracker.search("sunrise")
        #expect(hits == [TrackerHit(id: 7, title: "Sunrise", chapters: 40), TrackerHit(id: 8, title: "Dusk", chapters: nil)])
        let request = try #require(site.requests.first)
        #expect(request.url?.absoluteString == "https://graphql.anilist.co")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(body(request).contains("\"search\":\"sunrise\""))
    }

    @Test func sendsTheProgressToAniListWithTheToken() async throws {
        let site = FakeSite { _ in (200, ["data": ["SaveMediaListEntry": ["id": 1, "progress": 3]]]) }
        let tracker = Tracker(kind: .anilist, clientID: "1", token: "abc", fetcher: site.fetcher)
        try await tracker.setProgress(of: TrackLink(kind: .anilist, id: 7, title: "Sunrise"), chapters: 3, finished: false)
        let request = try #require(site.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        let sent = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        let variables = try #require(sent["variables"] as? [String: Any])
        #expect(variables["id"] as? Int == 7)
        #expect(variables["progress"] as? Int == 3)
        #expect(variables["status"] as? String == "CURRENT")
    }

    @Test func refusesAChangeWithNoToken() async {
        let site = FakeSite { _ in (200, [:]) }
        let tracker = Tracker(kind: .anilist, clientID: "1", token: nil, fetcher: site.fetcher)
        await #expect(throws: TrackerError.notSignedIn) {
            try await tracker.setProgress(of: TrackLink(kind: .anilist, id: 7, title: "S"), chapters: 1, finished: false)
        }
        #expect(site.requests.isEmpty, "No request goes out with no token.")
    }

    @Test func givesTheMessageOfAnAniListError() async {
        let site = FakeSite { _ in (200, ["errors": [["message": "Invalid token"]]]) }
        let tracker = Tracker(kind: .anilist, clientID: "1", token: "bad", fetcher: site.fetcher)
        await #expect(throws: TrackerError.refused("Invalid token")) { _ = try await tracker.search("x") }
    }

    @Test func readsTheTokenOfAniListFromTheFragment() async throws {
        let tracker = Tracker(kind: .anilist, clientID: "1", token: nil, fetcher: FakeSite { _ in (200, [:]) }.fetcher)
        let token = try await tracker.token(from: URL(string: "asabunko://anilist#access_token=xyz&token_type=Bearer&expires_in=3600")!, verifier: "")
        #expect(token == "xyz")
        let page = tracker.signInURL(verifier: "", state: "")
        #expect(page.absoluteString == "https://anilist.co/api/v2/oauth/authorize?client_id=1&response_type=token")
    }

    @Test func changesTheCodeOfMyAnimeListIntoAToken() async throws {
        let site = FakeSite { _ in (200, ["access_token": "mal-token", "token_type": "Bearer"]) }
        let tracker = Tracker(kind: .myanimelist, clientID: "cid", token: nil, fetcher: site.fetcher)
        let verifier = String(repeating: "v", count: 50)
        let page = URLComponents(url: tracker.signInURL(verifier: verifier, state: "s1"), resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: (page.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["code_challenge"] == verifier, "MyAnimeList takes the plain method, so the challenge is the verifier.")
        #expect(items["code_challenge_method"] == "plain")
        #expect(items["redirect_uri"] == "asabunko://myanimelist")
        let token = try await tracker.token(from: URL(string: "asabunko://myanimelist?code=c0de&state=s1")!, verifier: verifier)
        #expect(token == "mal-token")
        let request = try #require(site.requests.first)
        #expect(request.url?.absoluteString == "https://myanimelist.net/v1/oauth2/token")
        #expect(body(request) == "client_id=cid&code=c0de&code_verifier=\(verifier)&grant_type=authorization_code&redirect_uri=asabunko%3A%2F%2Fmyanimelist")
    }

    @Test func searchesAndPatchesMyAnimeListAtATestServer() async throws {
        let site = FakeSite { request in
            if request.httpMethod == "PATCH" { return (200, ["status": "reading", "num_chapters_read": 4]) }
            return (200, ["data": [["node": ["id": 21, "title": "Sunrise", "num_chapters": 0]]]])
        }
        let base = URL(string: "http://127.0.0.1:9/trackers")!
        let tracker = Tracker(kind: .myanimelist, clientID: "cid", token: "t", fetcher: site.fetcher, base: base)
        #expect(try await tracker.search("Sunrise") == [TrackerHit(id: 21, title: "Sunrise", chapters: nil)], "Zero chapters means that the count is not known.")
        try await tracker.setProgress(of: TrackLink(kind: .myanimelist, id: 21, title: "Sunrise"), chapters: 4, finished: true)
        let (search, patch) = (site.requests[0], site.requests[1])
        #expect(search.url?.path == "/trackers/myanimelist/manga")
        #expect(search.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        #expect(patch.url?.path == "/trackers/myanimelist/manga/21/my_list_status")
        #expect(body(patch) == "num_chapters_read=4&status=completed")
    }

    @Test func treatsAnExpiredTokenAsSignedOut() async {
        let site = FakeSite { _ in (401, ["error": "invalid_token"]) }
        let tracker = Tracker(kind: .myanimelist, clientID: "cid", token: "old", fetcher: site.fetcher)
        await #expect(throws: TrackerError.notSignedIn) { _ = try await tracker.search("x") }
    }

    @Test func sendsOnlyANumberThatGoesUp() {
        #expect(Tracker.progress(page: 3, pageCount: 10, finished: false, sent: 0) == 3, "The open chapter is not read yet.")
        #expect(Tracker.progress(page: 3, pageCount: 10, finished: false, sent: 3) == nil)
        #expect(Tracker.progress(page: 1, pageCount: 10, finished: false, sent: 3) == nil, "A step back does not go to the tracker.")
        #expect(Tracker.progress(page: 9, pageCount: 10, finished: true, sent: 3) == 10)
    }

    @Test func keepsTheLinksOfABook() throws {
        var book = Book(title: "A", fileName: "a", pageCount: 3)
        book.tracking = [TrackLink(kind: .anilist, id: 7, title: "Sunrise", sent: 2)]
        let read = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(book))
        #expect(read.tracking == book.tracking)
        let old = try JSONDecoder().decode(Book.self, from: Data(#"{"id":"\#(UUID().uuidString)","title":"B","format":"comic","fileName":"b","pageCount":1,"added":0,"page":0,"position":0,"finished":false}"#.utf8))
        #expect(old.tracking.isEmpty, "A book of an older version has no links.")
    }
}
