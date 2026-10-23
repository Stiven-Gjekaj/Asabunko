import Foundation
import Testing
@testable import AsaCore

/// A fetcher with fixed answers, by URL.
func fixedFetcher(_ pages: [String: (Int, String, String)], seen: SeenRequests? = nil) -> Fetcher {
    { request in
        seen?.add(request)
        let url = request.url!.absoluteString
        guard let page = pages[url] else { throw URLError(.cannotFindHost) }
        let response = HTTPURLResponse(url: request.url!, statusCode: page.0, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": page.1])!
        return (Data(page.2.utf8), response)
    }
}

final class SeenRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [URLRequest] = []
    func add(_ request: URLRequest) { lock.lock(); list.append(request); lock.unlock() }
    var all: [URLRequest] { lock.lock(); defer { lock.unlock() }; return list }
}

@Suite struct JSRuntimeTests {
    @Test func fetchesTextAndJSONWithHeadersAndABody() async throws {
        let seen = SeenRequests()
        let runtime = try JSRuntime(name: "test", fetcher: fixedFetcher([
            "https://a.test/page": (200, "text/html; charset=utf-8", "<p>Morning</p>"),
            "https://a.test/api": (200, "application/json", #"{"chapters": 3}"#),
        ], seen: seen))
        try runtime.evaluate("""
        globalThis.work = async function () {
          const page = await fetch('https://a.test/page', { headers: { 'X-Test': 'yes' } });
          const api = await (await fetch('https://a.test/api', { method: 'POST', body: JSON.stringify({ q: 1 }) })).json();
          return { ok: page.ok, text: await page.text(), chapters: api.chapters, type: page.headers.get('Content-Type') };
        };
        """)
        struct Answer: Decodable, Equatable { let ok: Bool; let text: String; let chapters: Int; let type: String }
        let answer = try await runtime.invoke(Answer.self, "work")
        #expect(answer == Answer(ok: true, text: "<p>Morning</p>", chapters: 3, type: "text/html; charset=utf-8"))
        #expect(seen.all.first?.value(forHTTPHeaderField: "X-Test") == "yes")
        #expect(seen.all.last?.httpMethod == "POST")
        #expect(seen.all.last?.httpBody == Data(#"{"q":1}"#.utf8))
    }

    @Test func parsesHTMLWithCheerioAndDatesWithDayjs() async throws {
        let runtime = try JSRuntime(name: "test", fetcher: fixedFetcher([:]))
        try runtime.evaluate("""
        globalThis.work = function () {
          const $ = __libraries.cheerio.load('<ul><li class="c"><a href="/c/1">One</a></li><li class="c"><a href="/c/2">Two</a></li></ul>');
          const links = $('li.c a').map((i, el) => ({ name: $(el).text(), path: $(el).attr('href') })).get();
          return { links, year: __libraries.dayjs('2026-10-23').year(), url: new URL('/x?y=1', 'https://a.test/b/').href };
        };
        """)
        struct Link: Decodable, Equatable { let name: String; let path: String }
        struct Answer: Decodable { let links: [Link]; let year: Int; let url: String }
        let answer = try await runtime.invoke(Answer.self, "work")
        #expect(answer.links == [Link(name: "One", path: "/c/1"), Link(name: "Two", path: "/c/2")])
        #expect(answer.year == 2026)
        #expect(answer.url == "https://a.test/x?y=1")
    }

    @Test func decodesTextInOtherEncodings() async throws {
        let runtime = try JSRuntime(name: "test", fetcher: fixedFetcher([:]))
        try runtime.evaluate("globalThis.work = (bytes) => new TextDecoder('shift_jis').decode(new Uint8Array(bytes));")
        let bytes = Array("朝の文庫".data(using: .shiftJIS)!).map(Int.init)
        let answer = try await runtime.invoke(String.self, "work", [bytes])
        #expect(answer == "朝の文庫")
    }

    @Test func waitsForATimer() async throws {
        let runtime = try JSRuntime(name: "test", fetcher: fixedFetcher([:]))
        try runtime.evaluate("globalThis.work = () => new Promise((resolve) => setTimeout(() => resolve('later'), 20));")
        #expect(try await runtime.invoke(String.self, "work") == "later")
    }

    @Test func givesTheMessageOfAnError() async throws {
        let runtime = try JSRuntime(name: "test", fetcher: fixedFetcher([:]))
        try runtime.evaluate("globalThis.work = async () => { throw new Error('No novel here'); };")
        await #expect(throws: JSRuntimeError.script("No novel here")) { try await runtime.invoke("work") }
        // A request that fails rejects with a TypeError, as fetch does in a browser.
        let name = try await runtime.invoke(String.self, "async () => { try { await fetch('https://nowhere.test/'); return 'no error'; } catch (e) { return e.name; } }")
        #expect(name == "TypeError")
    }

    @Test func stopsAScriptThatNeverAnswers() async throws {
        let runtime = try JSRuntime(name: "test", fetcher: fixedFetcher([:]))
        runtime.timeout = 0.2
        await #expect(throws: JSRuntimeError.timeout) { try await runtime.invoke("() => new Promise(() => {})") }
    }
}
