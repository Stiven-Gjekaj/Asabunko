import Foundation
import Testing
import WAT
@testable import AsaCore

/// A small source in WAT that answers as the register_source! macro of aidoku-rs does.
private func fakeSource() throws -> Data {
    Data(try wat2wasm(#"""
    (module
      (import "std" "buffer_len" (func $len (param i32) (result i32)))
      (import "std" "read_buffer" (func $read (param i32 i32 i32) (result i32)))
      (import "js" "context_create" (func $js (result i32)))
      (memory (export "memory") 1)
      ;; A result: total 26, capacity 0, and the postcard of a page with one series "1" "A" and a next page.
      (data (i32.const 64) "\1a\00\00\00\00\00\00\00\01\01\31\01\41\00\00\00\00\00\00\00\00\00\00\00\00\01")
      ;; An error message: -1, capacity, total 15, and "Bad".
      (data (i32.const 128) "\ff\ff\ff\ff\00\00\00\00\0f\00\00\00Bad")
      (global $freed (mut i32) (i32.const 0))
      (func (export "start"))
      (func (export "free_result") (param i32) (global.set $freed (i32.add (global.get $freed) (i32.const 1))))
      (func (export "freed") (result i32) (global.get $freed))
      ;; The first byte of the query, as the page number, so that the test sees the argument.
      (func (export "get_search_manga_list") (param $query i32) (param $page i32) (param $filters i32) (result i32)
        (if (i32.eq (local.get $page) (i32.const 9)) (then (return (i32.const 128))))
        (if (i32.eq (local.get $page) (i32.const 8)) (then (return (i32.const -3))))
        (drop (call $read (local.get $query) (i32.const 512) (call $len (local.get $query))))
        (i32.const 64))
      (func (export "query_byte") (result i32) (i32.load8_u (i32.const 512))))
    """#))
}

@Suite struct AidokuHostTests {
    private func host() throws -> AidokuHost {
        try AidokuHost(name: "fake", wasm: try fakeSource(), defaults: AidokuDefaults(file: nil, initial: [:]), fetcher: fixedFetcher([:]))
    }

    @Test func readsAResultAndFreesItOneTime() throws {
        let host = try host()
        let data = try host.queue.sync { try host.call("get_search_manga_list", [Data("Z".utf8), Int32(1), Data([0])]) }
        var r = PostcardReader(data)
        let page = try Aidoku.MangaPageResult.read(&r)
        #expect(page.entries.map(\.title) == ["A"])
        #expect(try host.queue.sync { AidokuHost.i32(try host.invoke("freed", [])[0]) } == 1)
        #expect(try host.queue.sync { AidokuHost.i32(try host.invoke("query_byte", [])[0]) } == 90)
    }

    @Test func givesTheMessageAndTheCodeOfAnError() throws {
        let host = try host()
        #expect(throws: AidokuHost.Failure.message("Bad")) { try host.queue.sync { try host.call("get_search_manga_list", [Data(), Int32(9), Data([0])]) } }
        #expect(throws: AidokuHost.Failure.code(-3)) { try host.queue.sync { try host.call("get_search_manga_list", [Data(), Int32(8), Data([0])]) } }
    }

    @Test func givesAStubToAnImportThatItDoesNotHave() throws {
        let functions = WasmImports.functions(in: [UInt8](try fakeSource()))
        #expect(functions.contains(WasmImports.Function(module: "js", name: "context_create", parameters: [], results: [.i32])))
        #expect(functions.contains(WasmImports.Function(module: "std", name: "read_buffer", parameters: [.i32, .i32, .i32], results: [.i32])))
    }

    @Test func readsTheListOfSourcesWithItsRelativeLinks() throws {
        let json = #"{"name":"Community","sources":[{"id":"en.guya","name":"Guya","version":2,"iconURL":"icons/en.guya-v2.png","downloadURL":"sources/en.guya-v2.aix","languages":["en"],"contentRating":0},{"id":"multi.x","name":"X","version":1,"downloadURL":"sources/x.aix","languages":["en","ja"],"contentRating":2},{"id":"en.novelbuddy","name":"NovelBuddy","version":8,"downloadURL":"sources/n.aix","languages":["en"]}]}"#
        let list = try AidokuIndex.parse(Data(json.utf8), url: URL(string: "https://aidoku.test/sources/index.min.json")!)
        #expect(list[0].code == URL(string: "https://aidoku.test/sources/sources/en.guya-v2.aix"))
        #expect(list[0].icon == URL(string: "https://aidoku.test/sources/icons/en.guya-v2.png"))
        #expect(list[1].language == "Multi")
        #expect(list[1].adult)
        #expect(list[2].novels)
        #expect(!list[0].novels)
    }

    @Test func turnsTheMarkdownOfANovelIntoHTML() {
        #expect(AidokuSource.html(fromMarkdown: "# One\n\nThe **sun** came *up* & <set>.") == "<h2>One</h2>\n<p>The <b>sun</b> came <i>up</i> &amp; &lt;set&gt;.</p>")
    }

    /// Runs real sources of Aidoku Community from the web. It runs only with ASABUNKO_LIVE=1.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ASABUNKO_LIVE"] == "1"), arguments: ["en.guya", "en.mangabat"])
    func readsARealSource(id: String) async throws {
        let session: Fetcher = { request in
            var request = request
            if request.value(forHTTPHeaderField: "User-Agent") == nil {
                request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, response as! HTTPURLResponse)
        }
        let listURL = URL(string: "https://aidoku-community.github.io/sources/index.min.json")!
        let list = try AidokuIndex.parse(try await session(URLRequest(url: listURL)).0, url: listURL)
        let info = try #require(list.first { $0.id == id })
        let file = try temporaryFolder().appendingPathComponent("\(id).aix")
        try await session(URLRequest(url: info.code)).0.write(to: file)
        let source = try AidokuSource(info: info, package: file, settings: nil, fetcher: session)
        let popular = try await source.popular(page: 1)
        #expect(!popular.items.isEmpty)
        let details = try await source.details(of: popular.items[0])
        #expect(!details.chapters.isEmpty)
        guard case let .pages(pages) = try await source.content(of: details.chapters.last!, in: details.series) else { Issue.record("no pages"); return }
        #expect(!pages.isEmpty)
        let found = try await source.search(String(popular.items[0].title.prefix(6)), page: 1)
        print("LIVE", id, popular.items.count, "series;", details.series.title, details.chapters.count, "chapters,", pages.count, "pages; search", found.items.count, "; first page", pages.first?.url?.absoluteString.prefix(80) ?? "")
    }
}
