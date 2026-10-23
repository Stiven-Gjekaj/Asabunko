import CommonCrypto
import Foundation
import Testing
@testable import AsaCore

/// An extension in the form of the Paperback toolchain: an IIFE that sets the global source.
private let bundle = #"""
var source = (function (e) {
  // The parts of the Form class of the toolchain that the forms of this extension use.
  class Form { reloadForm() { const id = this.__underlying_formId; if (id) Application.formDidChange(id); } }
  class LanguageForm extends Form {
    constructor() { super(); this.requiresExplicitSubmission = true; this.chosen = Application.getState('languages') ?? ['en']; }
    getSections() {
      return [{ type: 'listSection', id: 'languages', header: 'Languages', items: ['en', 'ja'].map((code) => {
        this['__closure_selector-' + code] = () => { this.chosen = this.chosen.includes(code) ? this.chosen.filter((c) => c !== code) : [...this.chosen, code]; };
        return { type: 'labelRow', id: code, title: code.toUpperCase(), isHidden: false, isSelectable: true,
                 value: this.chosen.includes(code) ? { symbol: 'checkmark', style: 'success' } : undefined, onSelect: Application.Selector(this, '__closure_selector-' + code) };
      }) }];
    }
    async formDidSubmit() { Application.setState(this.chosen, 'languages'); }
  }
  class SettingsForm extends Form {
    getSections() {
      return [
        { type: 'listSection', id: 'main', header: 'Main', footer: 'Changes go at once.', items: [
          { type: 'toggleRow', id: 'adult', title: 'Adult titles', value: Application.getState('adult') ?? false, onValueChange: Application.Selector(this, 'setAdult') },
          { type: 'inputRow', id: 'name', title: 'Name', value: Application.getState('name') ?? '', onValueChange: Application.Selector(this, 'setName') },
          { type: 'navigationRow', id: 'languages', title: 'Languages', value: (Application.getState('languages') ?? ['en']).join(', '), form: new LanguageForm() },
          { type: 'labelRow', id: 'secret', title: 'Secret', isHidden: true },
          { type: 'oauthButtonRow', id: 'login', title: 'Sign in' },
        ] },
        { type: 'listSection', id: 'reset', items: [{ type: 'buttonRow', id: 'reset', title: 'Reset', onSelect: Application.Selector(this, 'reset') }] },
      ];
    }
    async setAdult(value) { Application.setState(value, 'adult'); }
    async setName(value) { Application.setState(value, 'name'); }
    async reset() { Application.resetAllState(); this.reloadForm(); }
  }
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
    async getSettingsForm() { return new SettingsForm(); }
    async getSearchFilters() {
      return [{ type: 'dropdown', id: 'sort', title: 'Sort', options: [{ id: 'new', value: 'Newest' }, { id: 'top', value: 'Top' }], value: 'new' },
              { type: 'multiselect', id: 'genre', title: 'Genre', options: [{ id: 'calm', value: 'Calm' }, { id: 'loud', value: 'Loud' }], value: {}, allowExclusion: true }];
    }
    async getSearchResults(query, metadata) {
      const filters = (query.filters ?? []).map((f) => f.id + '=' + (typeof f.value === 'string' ? f.value : Object.keys(f.value).sort().map((k) => k + ':' + f.value[k]).join(','))).sort().join(';');
      return { items: [{ mangaId: 'm1', title: 'Found ' + query.title + (filters ? ' with ' + filters : ''), imageUrl: '' }], metadata: undefined };
    }
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

    @Test func searchesWithTheFiltersOfTheExtension() async throws {
        let source = try await load(SeenRequests(), state: try temporaryFolder().appendingPathComponent("state.json"))
        let filters = await source.filterOptions()
        #expect(filters.map(\.id) == ["sort", "genre"])
        #expect(filters[0].kind == .select([.init(label: "Newest", value: "new"), .init(label: "Top", value: "top")]))
        #expect(filters[1].kind == .multi([.init(label: "Calm", value: "calm"), .init(label: "Loud", value: "loud")], excludable: true))
        let page = try await source.browse(page: 1, query: "tea", filters: ["sort": .select("top"), "genre": .multi(included: ["calm"], excluded: ["loud"])])
        #expect(page.items.first?.title == "Found tea with genre=calm:included,loud:excluded;sort=top")
        #expect(try await source.browse(page: 1, query: "tea", filters: [:]).items.first?.title == "Found tea")
    }

    @Test func showsTheSettingsFormAndDoesTheActionsOfItsRows() async throws {
        let state = try temporaryFolder().appendingPathComponent("state.json")
        let source = try await load(SeenRequests(), state: state)
        #expect(await source.hasSettingsForm())
        let root = try #require(try await source.settingsForm())
        #expect(root.submit == false)
        #expect(root.sections.map(\.id) == ["main", "reset"])
        #expect(root.sections[0].header == "Main")
        #expect(root.sections[0].footer == "Changes go at once.")
        // The hidden row does not show. The app cannot do the sign-in row.
        #expect(root.sections[0].rows.map(\.id) == ["adult", "name", "languages", "login"])
        #expect(root.sections[0].rows.map(\.kind) == [.toggle, .input, .link, .unsupported])
        #expect(root.sections[0].rows[0].on == false)

        var form = try await source.formAction(root.id, row: "adult", input: .toggle(true))
        #expect(form.sections[0].rows[0].on == true)
        form = try await source.formAction(root.id, row: "name", input: .text("Mina"))
        #expect(form.sections[0].rows[1].value == "Mina")
        #expect(try String(contentsOf: state, encoding: .utf8).contains("Mina"))

        // A child form keeps its changes until the user saves it.
        let link = try #require(form.sections[0].rows[2].form)
        #expect(form.sections[0].rows[2].value == "en")
        var child = try await source.form(link)
        #expect(child.submit)
        #expect(child.sections[0].rows.map(\.mark) == ["included", nil])
        child = try await source.formAction(link, row: "ja", input: .tap)
        child = try await source.formAction(link, row: "en", input: .tap)
        #expect(child.sections[0].rows.map(\.mark) == [nil, "included"])
        #expect(try await source.form(root.id).sections[0].rows[2].value == "en")
        try await source.submitForm(link)
        #expect(try await source.form(root.id).sections[0].rows[2].value == "ja")

        // The reset button clears the state, and the form shows the values from the start.
        form = try await source.formAction(root.id, row: "reset", input: .tap)
        #expect(form.sections[0].rows[0].on == false)
        #expect(form.sections[0].rows[1].value == "")
        await #expect(throws: JSRuntimeError.self) { try await source.formAction(root.id, row: "secret", input: .tap) }
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
        // Each form of the settings opens, one level down from the root.
        if await source.hasSettingsForm() {
            let root = try #require(try await source.settingsForm())
            let links = root.sections.flatMap(\.rows).compactMap(\.form)
            var rows = 0
            for link in links { rows += try await source.form(link).sections.flatMap(\.rows).count }
            print("LIVE", id, "settings:", root.sections.count, "sections,", links.count, "forms with", rows, "rows")
        }
        print("LIVE", id, popular.items.count, "series;", details.series.title, details.chapters.count, "chapters,", pages.count, "pages; first", details.chapters.first?.title ?? "", "last", details.chapters.last?.title ?? "")
    }
}
