import CommonCrypto
import Foundation
import Testing
@testable import AsaCore

/// An extension in the form of the Paperback toolchain: an IIFE that sets the global source.
private let bundle = #"""
var source = (function (e) {
  class Quiet {
    constructor() { this.visits = Application.getState('visits') ?? 0; }
    async initialise() {
      Application.registerInterceptor('referer', Application.Selector(this, 'interceptRequest'), Application.Selector(this, 'interceptResponse'));
      Application.registerInterceptor('second', Application.Selector(this, 'addSecond'), Application.Selector(this, 'passResponse'));
    }
    async interceptRequest(request) { return { ...request, headers: { ...(request.headers ?? {}), referer: 'https://quiet.test/' } }; }
    async addSecond(request) { request.headers['x-second'] = request.headers.referer ? 'after-referer' : 'alone'; return request; }
    async interceptResponse(request, response, data) {
      if (response.cookies.length) Application.setState(response.cookies, 'cookies');
      return data;
    }
    async passResponse(request, response, data) { return data; }
    async getDiscoverSections() { return [{ id: 'popular', title: 'Popular', type: 1 }, { id: 'latest_updates', title: 'Latest', type: 3 }]; }
    async getDiscoverSectionItems(section, metadata) {
      const page = metadata ?? 1;
      const [, data] = await Application.scheduleRequest({ url: 'https://quiet.test/' + section.id + '?page=' + page, method: 'GET' });
      const list = JSON.parse(Application.arrayBufferToUTF8String(data));
      return { items: list.map((t) => ({ type: 'simpleCarouselItem', mangaId: t.id, title: t.title, imageUrl: 'https://quiet.test/c/' + t.id + '.jpg' })), metadata: list.length ? page + 1 : undefined };
    }
    async getSearchResults(query, metadata) { return { items: [{ mangaId: 'm1', title: 'Found ' + query.title, imageUrl: '' }], metadata: undefined }; }
    async getMangaDetails(mangaId) {
      return { mangaId, mangaInfo: { primaryTitle: 'Morning Tea', thumbnailUrl: 'https://quiet.test/c/m1.jpg', synopsis: '<p>Warm.</p>', secondaryTitles: [],
        contentRating: 'SAFE', author: 'Mina', status: 'Ongoing', tagGroups: [{ id: 'g', title: 'Genres', tags: [{ id: 'a', title: 'Calm' }] }] } };
    }
    async getChapters(manga) {
      return [2, 1].map((n) => ({ chapterId: 'c' + n, sourceManga: manga, langCode: 'en', chapNum: n, title: n === 1 ? 'Kettle' : 'Chapter 2', publishDate: new Date(Date.UTC(2026, 9, n)) }));
    }
    async getChapterDetails(chapter) {
      if (!(chapter.publishDate instanceof Date)) throw new Error('The chapter lost its date.');
      const key = await crypto.subtle.importKey('raw', new TextEncoder().encode('0123456789abcdef'), { name: 'AES-CBC' }, false, ['decrypt']);
      const secret = Application.base64Decode(Application.getState('secret'));
      const plain = await crypto.subtle.decrypt({ name: 'AES-CBC', iv: new TextEncoder().encode('fedcba9876543210') }, key, secret);
      const path = new TextDecoder().decode(plain);
      return { id: chapter.chapterId, mangaId: chapter.sourceManga.mangaId, pages: ['https://quiet.test/' + path + '/1.jpg', 'https://quiet.test/' + path + '/2.jpg#marker'] };
    }
  }
  return e.Quiet = new Quiet(), e.QuietExtension = Quiet, e;
})({});
"""#

private func encrypted(_ text: String) -> String {
    let key = Data("0123456789abcdef".utf8), iv = Data("fedcba9876543210".utf8), data = Data(text.utf8)
    var out = Data(count: data.count + 16)
    var moved = 0
    let size = out.count
    _ = out.withUnsafeMutableBytes { o in data.withUnsafeBytes { d in key.withUnsafeBytes { k in iv.withUnsafeBytes { v in
        CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), k.baseAddress, 16, v.baseAddress, d.baseAddress, data.count, o.baseAddress, size, &moved)
    } } } }
    return out.prefix(moved).base64EncodedString()
}

@Suite struct PaperbackTests {
    private let info = SourceInfo(id: "Quiet", name: "Quiet", language: "en", version: "1.0.0", icon: nil, code: URL(string: "https://repo.test/Quiet/index.js")!, novels: false)

    private func load(_ seen: SeenRequests, state: URL) async throws -> PaperbackExtension {
        let fetcher: Fetcher = { request in
            seen.add(request)
            let url = request.url!.absoluteString
            let body = url.contains("popular?page=1") ? #"[{"id":"m1","title":"Morning Tea"},{"id":"m2","title":"Rain Shop"}]"# : url.contains("latest") ? #"[{"id":"m3","title":"New"}]"# : "[]"
            let headers = ["Content-Type": "application/json", "Set-Cookie": "session=abc; Expires=Wed, 21 Oct 2099 07:28:00 GMT; Path=/"]
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!)
        }
        return try await PaperbackExtension(info: info, code: bundle, stateFile: state, userAgent: "Test", fetcher: fetcher)
    }

    @Test func pagesWithTheMetadataAndRunsTheInterceptorsInOrder() async throws {
        let seen = SeenRequests()
        let state = try temporaryFolder().appendingPathComponent("state.json")
        let source = try await load(seen, state: state)
        let first = try await source.popular(page: 1)
        #expect(first.items.map(\.title) == ["Morning Tea", "Rain Shop"])
        #expect(first.hasMore)
        #expect(try await source.popular(page: 2) == OnlinePage(items: [], hasMore: false))
        #expect(source.canShowLatest)
        #expect(try await source.latest(page: 1).items.map(\.id) == ["m3"])
        let request = try #require(seen.all.first)
        #expect(request.value(forHTTPHeaderField: "referer") == "https://quiet.test/")
        #expect(request.value(forHTTPHeaderField: "x-second") == "after-referer")
        #expect(source.imageRequest(URL(string: "https://quiet.test/c/m1.jpg")!).value(forHTTPHeaderField: "referer") == "https://quiet.test/")
        // The cookie of the answer stays in the state, with its date.
        let saved = try String(contentsOf: state, encoding: .utf8)
        #expect(saved.contains("session"))
        #expect(saved.contains("$date"))
    }

    @Test func readsTheSeriesTheChaptersAndThePagesWithTheStateAndTheCrypto() async throws {
        let seen = SeenRequests()
        let state = try temporaryFolder().appendingPathComponent("state.json")
        try Data(#"{"plain":{"secret":"\"\#(encrypted("chapter-one"))\""},"secure":{}}"#.utf8).write(to: state)
        let source = try await load(seen, state: state)
        let details = try await source.details(of: OnlineSeries(id: "m1", title: ""))
        #expect(details.series.title == "Morning Tea")
        #expect(details.summary == "Warm.")
        #expect(details.genres == ["Calm"])
        #expect(details.chapters.map(\.title) == ["Ch. 1: Kettle", "Ch. 2"])
        #expect(details.chapters.first?.date == "2026-10-01")
        guard case let .pages(pages) = try await source.content(of: details.chapters[0], in: details.series) else { Issue.record("no pages"); return }
        #expect(pages.map(\.url?.absoluteString) == ["https://quiet.test/chapter-one/1.jpg", "https://quiet.test/chapter-one/2.jpg"])
        #expect(pages.first?.value(forHTTPHeaderField: "referer") == "https://quiet.test/")
        #expect(try await source.search("rain", page: 1).items.map(\.title) == ["Found rain"])
    }

    @Test func readsTheRepositoryAndSkipsTheTrackers() throws {
        let json = #"{"buildTime":"x","builtWith":{"toolchain":"1","types":"1"},"repository":{"name":"Inkdex","description":""},"sources":[{"id":"Toonily","name":"Toonily","description":"","version":"1.0.1","icon":"icon.png","language":"en","contentRating":"ADULT","badges":[],"capabilities":[1,16,4,32,64],"developers":[]},{"id":"AniList","name":"AniList","description":"","version":"1","icon":"icon.png","language":"en","contentRating":"SAFE","badges":[],"capabilities":[4,2,32,64,8],"developers":[]}]}"#
        let list = try PaperbackIndex.parse(Data(json.utf8), url: URL(string: "https://inkdex.test/0.9/stable/versioning.json")!)
        #expect(list.map(\.id) == ["Toonily"])
        #expect(list[0].code == URL(string: "https://inkdex.test/0.9/stable/Toonily/index.js"))
        #expect(list[0].icon == URL(string: "https://inkdex.test/0.9/stable/Toonily/static/icon.png"))
        #expect(list[0].adult)
    }

    /// Runs real extensions of Inkdex from the web. It runs only with ASABUNKO_LIVE=1.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ASABUNKO_LIVE"] == "1"), arguments: ["WeebCentral", "MangaDex"])
    func readsARealExtension(id: String) async throws {
        let agent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        let session: Fetcher = { request in
            var request = request
            if request.value(forHTTPHeaderField: "User-Agent") == nil { request.setValue(agent, forHTTPHeaderField: "User-Agent") }
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, response as! HTTPURLResponse)
        }
        let repo = URL(string: "https://inkdex.github.io/extensions/0.9/stable/versioning.json")!
        let info = try #require(try PaperbackIndex.parse(try await session(URLRequest(url: repo)).0, url: repo).first { $0.id == id })
        let code = String(decoding: try await session(URLRequest(url: info.code)).0, as: UTF8.self)
        let source = try await PaperbackExtension(info: info, code: code, stateFile: nil, userAgent: agent, fetcher: session)
        let popular = try await source.popular(page: 1)
        #expect(!popular.items.isEmpty)
        let details = try await source.details(of: popular.items[0])
        #expect(!details.chapters.isEmpty)
        guard case let .pages(pages) = try await source.content(of: details.chapters.last!, in: details.series) else { Issue.record("no pages"); return }
        print("LIVE", id, popular.items.count, "series;", details.series.title, details.chapters.count, "chapters,", pages.count, "pages; first", details.chapters.first?.title ?? "", "last", details.chapters.last?.title ?? "")
    }
}
