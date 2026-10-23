import Foundation
import Testing
@testable import AsaCore

/// A plugin in the form that the LNReader build gives: CommonJS, with require() and exports.default.
private let plugin = #"""
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
var fetch_1 = require("@libs/fetch");
var cheerio_1 = require("cheerio");
var novelStatus_1 = require("@libs/novelStatus");
var storage_1 = require("@libs/storage");
var Quiet = /** @class */ (function () {
  function Quiet() {
    this.id = "quiet"; this.name = "Quiet Novels"; this.site = "https://quiet.test/"; this.version = "1.0.0";
    this.imageRequestInit = { headers: { Referer: "https://quiet.test/" } };
    this.filters = { sort: { type: "Picker", label: "Sort", value: "popular", options: [] } };
  }
  Quiet.prototype.popularNovels = async function (page, options) {
    storage_1.storage.set("last", page);
    var kind = options.showLatestNovels ? "latest" : options.filters.sort.value;
    var html = await (0, fetch_1.fetchText)(this.site + "list/" + kind + "?page=" + page);
    var $ = (0, cheerio_1.load)(html);
    return $(".novel").map(function (i, el) {
      return { name: $(el).find("a").text(), path: $(el).find("a").attr("href"), cover: $(el).find("img").attr("src") };
    }).get();
  };
  Quiet.prototype.searchNovels = async function (term, page) {
    var res = await (0, fetch_1.fetchApi)(this.site + "search?q=" + encodeURIComponent(term));
    var data = await res.json();
    return data.results.map(function (r) { return { name: r.title, path: r.slug }; });
  };
  Quiet.prototype.parseNovel = async function (path) {
    var $ = (0, cheerio_1.load)(await (0, fetch_1.fetchText)(this.site + path));
    return {
      path: path, name: $("h1").text(), cover: $(".cover").attr("src"), summary: $(".summary").text().trim(),
      author: $(".author").text(), status: novelStatus_1.NovelStatus.Ongoing, genres: "Slice of Life, Drama",
      chapters: $(".chapter a").map(function (i, el) { return { name: $(el).text(), path: $(el).attr("href"), releaseTime: "2026-10-0" + (i + 1) }; }).get()
    };
  };
  Quiet.prototype.parseChapter = async function (path) {
    var $ = (0, cheerio_1.load)(await (0, fetch_1.fetchText)(this.site + path));
    return $("#content").html();
  };
  return Quiet;
}());
exports.default = new Quiet();
"""#

private let site: [String: (Int, String, String)] = [
    "https://quiet.test/list/popular?page=1": (200, "text/html", #"<div class="novel"><img src="https://quiet.test/c/1.jpg"><a href="novel/dawn">Dawn Tea</a></div><div class="novel"><img src="/c/2.jpg"><a href="novel/rain">Rain Shop</a></div>"#),
    "https://quiet.test/list/latest?page=1": (200, "text/html", #"<div class="novel"><a href="novel/new">New One</a></div>"#),
    "https://quiet.test/list/popular?page=2": (200, "text/html", "<p>No more</p>"),
    "https://quiet.test/search?q=tea%20time": (200, "application/json", #"{"results": [{"title": "Dawn Tea", "slug": "novel/dawn"}]}"#),
    "https://quiet.test/novel/dawn": (200, "text/html", #"""
        <h1>Dawn Tea</h1><img class="cover" src="https://quiet.test/c/1.jpg"><p class="summary"> A shop opens at dawn. </p>
        <span class="author">Mina</span><ul><li class="chapter"><a href="novel/dawn/1">First Cup</a></li><li class="chapter"><a href="novel/dawn/2">Second Cup</a></li></ul>
        """#),
    "https://quiet.test/novel/dawn/1": (200, "text/html; charset=utf-8", #"<div id="content"><p>The kettle sang.</p></div>"#),
]

@Suite struct LNReaderTests {
    private func load() async throws -> LNReaderPlugin {
        let info = SourceInfo(id: "quiet", name: "Quiet Novels", language: "English", version: "1.0.0", icon: nil, code: URL(string: "https://x.test/q.js")!, novels: true)
        return try await LNReaderPlugin(info: info, code: plugin, fetcher: fixedFetcher(site))
    }

    @Test func listsThePopularAndTheLatestNovels() async throws {
        let source = try await load()
        let popular = try await source.popular(page: 1)
        #expect(popular.items == [
            OnlineSeries(id: "novel/dawn", title: "Dawn Tea", cover: URL(string: "https://quiet.test/c/1.jpg")),
            OnlineSeries(id: "novel/rain", title: "Rain Shop", cover: URL(string: "https://quiet.test/c/2.jpg")),
        ])
        #expect(popular.hasMore)
        #expect(try await source.popular(page: 2).hasMore == false)
        #expect(try await source.latest(page: 1).items.map(\.title) == ["New One"])
    }

    @Test func searches() async throws {
        let source = try await load()
        #expect(try await source.search("tea time", page: 1).items.map(\.id) == ["novel/dawn"])
    }

    @Test func readsANovelAndAChapter() async throws {
        let source = try await load()
        let details = try await source.details(of: OnlineSeries(id: "novel/dawn", title: "Dawn"))
        #expect(details.series.title == "Dawn Tea")
        #expect(details.author == "Mina")
        #expect(details.summary == "A shop opens at dawn.")
        #expect(details.status == "Ongoing")
        #expect(details.genres == ["Slice of Life", "Drama"])
        #expect(details.chapters == [
            OnlineChapter(id: "novel/dawn/1", title: "First Cup", date: "2026-10-01"),
            OnlineChapter(id: "novel/dawn/2", title: "Second Cup", date: "2026-10-02"),
        ])
        #expect(try await source.content(of: details.chapters[0], in: details.series) == .html("<p>The kettle sang.</p>"))
        #expect(source.imageRequest(URL(string: "https://quiet.test/c/1.jpg")!).value(forHTTPHeaderField: "Referer") == "https://quiet.test/")
    }

    @Test func givesTheConstantsOfTheAppToAPlugin() async throws {
        let code = """
        const { defaultCover } = require('@/types/constants');
        exports.default = { id: 'c', name: 'C', site: 'https://c.test/', version: '1',
          async popularNovels() { return [{ name: 'One', path: 'n/1', cover: defaultCover }]; },
          async searchNovels() { return []; }, async parseNovel(path) { return { path, name: 'One', chapters: [] }; }, async parseChapter() { return ''; } };
        """
        let info = SourceInfo(id: "c", name: "C", language: "English", version: "1", icon: nil, code: URL(string: "https://x.test/c.js")!, novels: true)
        let source = try await LNReaderPlugin(info: info, code: code, fetcher: fixedFetcher([:]))
        let cover = try #require(try await source.popular(page: 1).items.first?.cover)
        #expect(cover.absoluteString.contains("coverNotAvailable"))
    }

    @Test func callsAGRPCSourceWithProtobuf() async throws {
        let code = """
        const { fetchProto } = require('@libs/fetch');
        const proto = 'syntax = "proto3"; message Ask { int32 id = 1; } message Reply { string name = 1; int64 count = 2; }';
        exports.default = { id: 'p', name: 'P', site: 'https://p.test/', version: '1',
          async popularNovels() {
            const reply = await fetchProto({ proto, requestType: 'Ask', responseType: 'Reply', requestData: { id: 7 } }, 'https://p.test/api.Ask');
            return [{ name: reply.name + ' ' + reply.count, path: 'n/1' }];
          },
          async searchNovels() { return []; }, async parseNovel(path) { return { path, name: 'N', chapters: [] }; }, async parseChapter() { return ''; } };
        """
        let seen = SeenRequests()
        let fetcher: Fetcher = { request in
            seen.add(request)
            // Reply { name: "Tide", count: 300 } in a gRPC frame.
            let message: [UInt8] = [0x0A, 0x04] + Array("Tide".utf8) + [0x10, 0xAC, 0x02]
            let body = Data([0, 0, 0, 0, UInt8(message.count)] + message)
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/grpc-web+proto"])!)
        }
        let info = SourceInfo(id: "p", name: "P", language: "English", version: "1", icon: nil, code: URL(string: "https://x.test/p.js")!, novels: true)
        let source = try await LNReaderPlugin(info: info, code: code, fetcher: fetcher)
        #expect(try await source.popular(page: 1).items.first?.title == "Tide 300")
        let request = try #require(seen.all.first)
        #expect(request.httpMethod == "POST")
        #expect(request.httpBody.map([UInt8].init) == [0, 0, 0, 0, 2, 0x08, 0x07], "The request is Ask { id: 7 } in a frame.")
    }

    @Test func refusesAFileThatIsNotAPlugin() async throws {
        let info = SourceInfo(id: "x", name: "X", language: "", version: "1", icon: nil, code: URL(string: "https://x.test/x.js")!, novels: true)
        await #expect(throws: JSRuntimeError.script("The file is not an LNReader plugin.")) {
            _ = try await LNReaderPlugin(info: info, code: "exports.default = {};", fetcher: fixedFetcher([:]))
        }
    }

    @Test func readsTheIndexWithTheBracketsOfItsURLs() throws {
        let json = #"[{"id":"anf","name":"AllNovelFull","site":"https://a.test/","lang":"‎English","version":"1.0.0","url":"https://raw.test/AllNovelFull[readnovelfull].js","iconUrl":"https://raw.test/i.png"}]"#
        let list = try LNReaderIndex.parse(Data(json.utf8))
        #expect(list.first?.language == "English")
        #expect(list.first?.code.absoluteString == "https://raw.test/AllNovelFull%5Breadnovelfull%5D.js")
    }

    /// Reads a real plugin from the web. It runs only with ASABUNKO_LIVE=1, because it needs the network.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ASABUNKO_LIVE"] == "1"))
    func readsARealPlugin() async throws {
        let session: Fetcher = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, response as! HTTPURLResponse)
        }
        let index = try LNReaderIndex.parse(try await session(URLRequest(url: URL(string: "https://raw.githubusercontent.com/LNReader/lnreader-plugins/plugins/v3.0.0/.dist/plugins.min.json")!)).0)
        let info = try #require(index.first { $0.id == "anf.net" })
        let code = String(decoding: try await session(URLRequest(url: info.code)).0, as: UTF8.self)
        let source = try await LNReaderPlugin(info: info, code: code, fetcher: session)
        let popular = try await source.popular(page: 1)
        #expect(!popular.items.isEmpty)
        let details = try await source.details(of: popular.items[0])
        #expect(!details.chapters.isEmpty)
        guard case let .html(text) = try await source.content(of: details.chapters[0], in: details.series) else { return }
        #expect(text.count > 200)
        print("LIVE", popular.items[0].title, details.chapters.count, "chapters,", text.count, "characters in the first")
    }

    /// Searches a real plugin with a text filter for the words of a search, and another filter. It runs only with ASABUNKO_LIVE=1.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ASABUNKO_LIVE"] == "1"), arguments: ["WTRLAB", "novelbuddy"])
    func searchesARealPluginWithFilters(id: String) async throws {
        let session: Fetcher = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, response as! HTTPURLResponse)
        }
        let index = try LNReaderIndex.parse(try await session(URLRequest(url: URL(string: "https://raw.githubusercontent.com/LNReader/lnreader-plugins/plugins/v3.0.0/.dist/plugins.min.json")!)).0)
        let info = try #require(index.first { $0.id.lowercased() == id.lowercased() }, "The list has \(id).")
        let code = String(decoding: try await session(URLRequest(url: info.code)).0, as: UTF8.self)
        let source = try await LNReaderPlugin(info: info, code: code, fetcher: session)
        let options = await source.filterOptions()
        let words = try #require(options.first { LNReaderPlugin.searchFilters.contains($0.id) }, "\(id) has a filter for the words.")
        let plain = try await source.search("sword", page: 1)
        let filtered = try await source.browse(page: 1, query: "sword", filters: [:])
        print("LIVE search", id, words.id, "plain", plain.items.prefix(3).map(\.title), "with filters", filtered.items.prefix(3).map(\.title))
        #expect(!filtered.items.isEmpty, "The list of the plugin does the search.")
    }
}
