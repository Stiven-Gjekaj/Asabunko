#!/usr/bin/env python3
"""A small server for the UI tests of the sources.

Under /opds/, it asks for the user "asa" with the password "morning". It
serves a catalog, an OpenSearch search, one comic as a CBZ, and the pages of
the comic one at a time with the Page Streaming Extension.

Under /lnreader/, it serves a list of LNReader plugins with one plugin, and
under /site/ the web site that the plugin reads.

Under /aidoku/, it serves a list of Aidoku sources with one source. The source
is a small WebAssembly module that this script writes. It gives one series of
one chapter of two pages, from /pages/.

Under /paperback/, it serves a repository of Paperback 0.9 extensions with
one extension. Its interceptor adds a referer, which the pages need.

Under /suwayomi/, it answers the GraphQL queries of a Suwayomi server with
one source, one series, and one chapter of three pages, with the same user
name and password as /opds/.

Under /cf/, each path of the server is behind a browser check, as a site
behind Cloudflare. The page of the check sets the cookie of a passed check.

/control/offline makes the server refuse the pages, and /control/online
gives them again.

It makes each file in memory.

Usage: python3 scripts/test-server.py [port]
"""
import base64
import io
import json
import struct
import sys
import zipfile
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PAGES = 4
AUTH = "Basic " + base64.b64encode(b"asa:morning").decode()


def png(width, height, rgb):
    """A PNG of one colour, with no library."""
    row = b"\x00" + bytes(rgb) * width
    raw = row * height
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")


def page(number):
    colours = [(230, 200, 180), (180, 210, 230), (200, 230, 180), (230, 230, 170)]
    return png(400, 600, colours[number % len(colours)])


def cbz():
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        for number in range(PAGES):
            archive.writestr(f"page{number + 1}.png", page(number))
        archive.writestr("ComicInfo.xml", "<ComicInfo><Series>Server Sunrise</Series><Number>1</Number><Manga>YesAndRightToLeft</Manga></ComicInfo>")
    return buffer.getvalue()


ATOM = "application/atom+xml;profile=opds-catalog"

CATALOG = f"""<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>root</id><title>Test Library</title>
  <link rel="search" type="application/opensearchdescription+xml" href="/opds/search.xml"/>
  <entry><id>all</id><title>All books</title><content>Every book on the server</content>
    <link rel="subsection" type="{ATOM};kind=navigation" href="/opds/all"/></entry>
</feed>"""


def books(title):
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:pse="http://vaemendis.net/opds-pse/ns">
  <id>all</id><title>{title}</title>
  <entry><id>urn:book:1</id><title>Server Sunrise 1</title><author><name>Test Author</name></author>
    <summary>A comic from the test server.</summary>
    <link rel="http://opds-spec.org/image/thumbnail" type="image/png" href="/pages/0"/>
    <link rel="http://opds-spec.org/acquisition" type="application/vnd.comicbook+zip" href="/files/sunrise.cbz"/>
    <link rel="http://vaemendis.net/opds-pse/stream" type="image/png" pse:count="{PAGES}" href="/pages/{{pageNumber}}?width={{maxWidth}}"/>
  </entry>
</feed>"""


SEARCH = """<?xml version="1.0"?><OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
<Url type="application/atom+xml;profile=opds-catalog" template="/opds/find?q={searchTerms}"/></OpenSearchDescription>"""


PLUGIN = r"""
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
var fetch_1 = require("@libs/fetch");
var cheerio_1 = require("cheerio");
var storage_1 = require("@libs/storage");
var Quiet = (function () {
  function Quiet() {
    this.id = "quiet"; this.name = "Quiet Novels"; this.site = "SITE"; this.version = "1.0.0";
    this.filters = { shelf: { label: "Shelf", type: "Picker", value: "all", options: [{ label: "All", value: "all" }, { label: "Finished", value: "done" }] } };
    this.pluginSettings = { stars: { label: "Show stars", value: false, type: "Switch" } };
  }
  Quiet.prototype.popularNovels = async function (page, options) {
    var star = storage_1.storage.get("stars") ? "\u2605 " : "";
    if (options && options.filters && options.filters.shelf && options.filters.shelf.value === "done") {
      return page === 1 ? [{ name: star + "Finished Shelf", path: "novel/dawn" }] : [];
    }
    var $ = (0, cheerio_1.load)(await (0, fetch_1.fetchText)(this.site + "list?page=" + page));
    return $(".novel a").map(function (i, el) { return { name: star + $(el).text(), path: $(el).attr("href"), cover: $(el).attr("data-cover") }; }).get();
  };
  Quiet.prototype.searchNovels = async function (term, page) { return this.popularNovels(page, {}); };
  Quiet.prototype.parseNovel = async function (path) {
    var $ = (0, cheerio_1.load)(await (0, fetch_1.fetchText)(this.site + path));
    return { path: path, name: $("h1").text(), author: $(".author").text(), summary: $(".summary").text(),
      chapters: $(".chapter a").map(function (i, el) { return { name: $(el).text(), path: $(el).attr("href") }; }).get() };
  };
  Quiet.prototype.parseChapter = async function (path) {
    return (0, cheerio_1.load)(await (0, fetch_1.fetchText)(this.site + path))("#content").html();
  };
  return Quiet;
}());
exports.default = new Quiet();
"""

PAPERBACK = r"""
var source = (function (e) {
  // A settings form with a switch, and a link to a form of choices that the user must save.
  class StyleForm {
    constructor() { this.requiresExplicitSubmission = true; this.style = Application.getState('style') ?? 'plain'; }
    getSections() {
      return [{ type: 'listSection', id: 'styles', header: 'Title style', items: ['plain', 'stars'].map((style) => {
        this['__closure_selector-' + style] = () => { this.style = style; };
        return { type: 'labelRow', id: style, title: style === 'plain' ? 'Plain' : 'Stars', isHidden: false,
                 value: this.style === style ? { symbol: 'checkmark', style: 'success' } : undefined, onSelect: Application.Selector(this, '__closure_selector-' + style) };
      }) }];
    }
    async formDidSubmit() { Application.setState(this.style, 'style'); }
  }
  class SettingsForm {
    getSections() {
      return [{ type: 'listSection', id: 'look', header: 'Look', items: [
        { type: 'toggleRow', id: 'loud', title: 'Capital letters', isHidden: false, value: Application.getState('loud') ?? false, onValueChange: Application.Selector(this, 'setLoud') },
        { type: 'navigationRow', id: 'style', title: 'Title style', isHidden: false, value: Application.getState('style') ?? 'plain', form: new StyleForm() },
      ] }];
    }
    async setLoud(value) { Application.setState(value, 'loud'); }
  }
  // The settings change the titles of the list.
  function titled(title) {
    const loud = Application.getState('loud') ? title.toUpperCase() : title;
    return Application.getState('style') === 'stars' ? '\u2605 ' + loud : loud;
  }
  class Quiet {
    async getSettingsForm() { return new SettingsForm(); }
    async initialise() {
      Application.registerInterceptor('referer', Application.Selector(this, 'interceptRequest'), Application.Selector(this, 'interceptResponse'));
    }
    async interceptRequest(request) { return { ...request, headers: { ...(request.headers ?? {}), referer: 'BASE/' } }; }
    async interceptResponse(request, response, data) { return data; }
    async getDiscoverSections() { return [{ id: 'popular', title: 'Popular', type: 1 }]; }
    async getDiscoverSectionItems(section, metadata) {
      const [, data] = await Application.scheduleRequest({ url: 'BASE/paperback/api/popular', method: 'GET' });
      const list = JSON.parse(Application.arrayBufferToUTF8String(data));
      return { items: list.map((t) => ({ type: 'simpleCarouselItem', mangaId: t.id, title: titled(t.title), imageUrl: 'BASE/paperback/page/1' })), metadata: undefined };
    }
    async getSearchResults(query) { return { items: [], metadata: undefined }; }
    async getMangaDetails(mangaId) {
      return { mangaId, mangaInfo: { primaryTitle: 'Paper Moon', thumbnailUrl: 'BASE/paperback/page/1', synopsis: 'A comic from JavaScript.',
        secondaryTitles: [], contentRating: 'SAFE', author: 'Script Artist' } };
    }
    async getChapters(manga) { return [{ chapterId: 'p1', sourceManga: manga, langCode: 'en', chapNum: 1, title: 'Lanterns' }]; }
    async getChapterDetails(chapter) {
      return { id: chapter.chapterId, mangaId: chapter.sourceManga.mangaId, pages: ['BASE/paperback/page/2', 'BASE/paperback/page/3'] };
    }
  }
  return e.Quiet = new Quiet(), e;
})({});
"""

SITE = {
    "list": '<div class="novel"><a href="novel/dawn" data-cover="/pages/1">Dawn Tea</a></div>',
    "novel/dawn": '<h1>Dawn Tea</h1><span class="author">Mina</span><p class="summary">A shop opens at dawn.</p>'
                  '<ul><li class="chapter"><a href="novel/dawn/1">First Cup</a></li><li class="chapter"><a href="novel/dawn/2">Second Cup</a></li></ul>',
    "novel/dawn/1": '<div id="content"><p>The kettle sang in the small shop.</p></div>',
    "novel/dawn/2": '<div id="content"><p>Rain came in the afternoon.</p></div>',
}



def postcard_string(text):
    data = text.encode()
    return leb(len(data)) + data


def leb(value):
    out = b""
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out += bytes([byte | 0x80])
        else:
            return out + bytes([byte])


def sleb(value):
    out = b""
    while True:
        byte = value & 0x7F
        value >>= 7
        if (value == 0 and not byte & 0x40) or (value == -1 and byte & 0x40):
            return out + bytes([byte])
        out += bytes([byte | 0x80])


def aidoku_wasm(host):
    """A WebAssembly module that answers as the register_source! macro of aidoku-rs, with fixed results."""
    cover = f"http://{host}/pages/2"
    some = lambda data: b"\x01" + data
    none = b"\x00"
    manga_head = postcard_string("m1") + postcard_string("Aidoku Sunrise") + some(postcard_string(cover))
    search = leb(1) + manga_head + none * 5 + b"\x00\x00\x00\x00" + none + none + b"\x00"
    chapter = postcard_string("c1") + some(postcard_string("Opening")) + some(struct.pack("<f", 1.0)) + none * 6 + b"\x00"
    update = (manga_head + none + some(leb(1) + postcard_string("Wasm Artist")) + some(postcard_string("A comic from WebAssembly."))
              + none + none + b"\x01\x00\x00\x00" + none + some(leb(1) + chapter))
    page = lambda n: b"\x00" + postcard_string(f"http://{host}/pages/{n}") + none + none + b"\x00" + none
    pages = leb(2) + page(1) + page(3)
    results = [(1024, search), (4096, update), (8192, pages)]

    def section(sid, body):
        return bytes([sid]) + leb(len(body)) + body

    def vec(items):
        return leb(len(items)) + b"".join(items)

    i32 = b"\x7f"
    types = vec([b"\x60" + vec([]) + vec([]), b"\x60" + vec([i32]) + vec([]),
                 b"\x60" + vec([i32, i32, i32]) + vec([i32]), b"\x60" + vec([i32, i32]) + vec([i32])])
    functions = vec([leb(0), leb(1), leb(2), leb(2), leb(3)])
    memory = vec([b"\x00" + leb(1)])
    names = ["start", "free_result", "get_search_manga_list", "get_manga_update", "get_page_list"]
    exports = vec([postcard_string("memory") + b"\x02" + leb(0)] + [postcard_string(n) + b"\x00" + leb(i) for i, n in enumerate(names)])
    body = lambda code: leb(len(b"\x00" + code)) + b"\x00" + code
    returns = lambda offset: b"\x41" + sleb(offset) + b"\x0b"
    code = vec([body(b"\x0b"), body(b"\x0b")] + [body(returns(offset)) for offset, _ in results])
    data = vec([b"\x00\x41" + sleb(offset) + b"\x0b" + leb(len(payload) + 8) + struct.pack("<ii", len(payload) + 8, 0) + payload
                for offset, payload in results])
    return (b"\x00asm\x01\x00\x00\x00" + section(1, types) + section(3, functions) + section(5, memory)
            + section(7, exports) + section(10, code) + section(11, data))


def aidoku_package(host):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr("Payload/main.wasm", aidoku_wasm(host))
        archive.writestr("Payload/source.json", json.dumps({"info": {"id": "en.test", "name": "Test Aidoku", "version": 1,
                                                                    "url": f"http://{host}", "languages": ["en"]}}))
        archive.writestr("Payload/filters.json", json.dumps([{"type": "range", "id": "year", "title": "Year", "min": 1990, "max": 2030}]))
    return buffer.getvalue()


def suwayomi(query):
    """The answer of the small Suwayomi server to a GraphQL query, by a word in it."""
    if "sources {" in query:
        return {"sources": {"nodes": [{"id": "0", "name": "Local source", "lang": "localsourcelang"},
                                       {"id": "777", "name": "Test Comics", "displayName": "Test Comics (EN)", "lang": "en",
                                        "iconUrl": "/pages/3", "isNsfw": False, "supportsLatest": True}]}}
    if "fetchSourceManga" in query:
        return {"fetchSourceManga": {"hasNextPage": False, "mangas": [{"id": 5, "title": "Morning Strip", "thumbnailUrl": "/pages/0"}]}}
    if "fetchManga" in query:
        return {"fetchManga": {"manga": {"id": 5, "title": "Morning Strip", "thumbnailUrl": "/pages/0", "author": "Test Artist",
                                          "artist": "Test Artist", "description": "A strip from the server.", "genre": ["Comedy"], "status": "ONGOING"}},
                "fetchChapters": {"chapters": [{"id": 51, "name": "Chapter 1", "chapterNumber": 1, "uploadDate": "1790000000000",
                                                "scanlator": None, "sourceOrder": 0}]}}
    if "fetchChapterPages" in query:
        return {"fetchChapterPages": {"pages": ["/suwayomi/api/v1/page/1", "/suwayomi/api/v1/page/2", "/suwayomi/api/v1/page/3"]}}
    return None


# The number of downloads of the Aidoku package, for the test of the source list.
DOWNLOADS = {"aix": 0}
OFFLINE = {"on": False}


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path.split("?")[0] != "/suwayomi/api/graphql":
            self.send_response(404)
            self.end_headers()
            return
        if self.headers.get("Authorization") != AUTH:
            self.send_response(401)
            self.end_headers()
            return
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))) or b"{}")
        data = suwayomi(body.get("query", ""))
        reply = {"data": data} if data is not None else {"errors": [{"message": "unknown query"}]}
        self.reply(json.dumps(reply).encode(), "application/json")

    def do_GET(self):
        path = self.path.split("?")[0]
        host = self.headers.get("Host")
        # Under /cf/, the server acts as a site behind the browser check of Cloudflare. The page of the
        # check sets the cookie of a passed check and loads again. With the cookie, the path works.
        if path.startswith("/cf/"):
            if "cf_clearance=passed" not in (self.headers.get("Cookie") or ""):
                challenge = (b"<!DOCTYPE html><html><head><title>Just a moment...</title></head><body>"
                        b"<p>Checking your browser.</p><script src=\"/cdn-cgi/challenge-platform/h/b/orchestrate\"></script>"
                        b"<script>document.cookie = 'cf_clearance=passed; path=/'; setTimeout(function () { location.reload(); }, 300);</script>"
                        b"</body></html>")
                self.send_response_only(503)
                self.send_header("Server", "cloudflare")
                self.send_header("Content-Type", "text/html")
                self.send_header("Content-Length", str(len(challenge)))
                self.end_headers()
                return self.wfile.write(challenge)
            self.path = self.path[3:]
            path = path[3:]
        if path in ("/control/offline", "/control/online"):
            OFFLINE["on"] = path.endswith("offline")
            return self.reply(b"ok", "text/plain")
        if OFFLINE["on"] and ("/page" in path or path.startswith("/pages/")):
            self.send_response(503)
            self.end_headers()
            return
        if path == "/paperback/versioning.json":
            repo = {"buildTime": "2026-10-23", "builtWith": {"toolchain": "1.0.0", "types": "1.0.0"},
                    "repository": {"name": "Test repository", "description": ""},
                    "sources": [{"id": "Quiet", "name": "Quiet Paper", "description": "", "version": "1.0.0", "icon": "icon.png",
                                 "language": "en", "contentRating": "SAFE", "badges": [], "capabilities": [1, 4, 64], "developers": []}]}
            return self.reply(json.dumps(repo).encode(), "application/json")
        if path == "/paperback/Quiet/index.js":
            return self.reply(PAPERBACK.replace("BASE", f"http://{host}").encode(), "application/javascript")
        if path == "/paperback/Quiet/static/icon.png":
            return self.reply(page(1), "image/png")
        if path == "/paperback/api/popular":
            return self.reply(b'[{"id": "moon", "title": "Paper Moon"}]', "application/json")
        if path.startswith("/paperback/page/"):
            if self.headers.get("Referer") != f"http://{host}/":
                self.send_response(403)
                self.end_headers()
                return
            return self.reply(page(int(path.rsplit("/", 1)[1])), "image/png")
        if path == "/aidoku/index.min.json":
            index = {"name": "Test list", "sources": [{"id": "en.test", "name": "Test Aidoku", "version": 1, "iconURL": "../pages/3",
                                                        "downloadURL": "sources/en.test-v1.aix", "languages": ["en"], "contentRating": 0},
                                                       {"id": "ja.test", "name": "Japanese Test", "version": 1, "iconURL": "../pages/3",
                                                        "downloadURL": "sources/en.test-v1.aix", "languages": ["ja"], "contentRating": 0}]}
            return self.reply(json.dumps(index).encode(), "application/json")
        if path == "/aidoku/sources/en.test-v1.aix":
            DOWNLOADS["aix"] += 1
            return self.reply(aidoku_package(host), "application/zip")
        if path == "/aidoku/downloads":
            return self.reply(str(DOWNLOADS["aix"]).encode(), "text/plain")
        if path == "/lnreader/plugins.min.json":
            index = f'[{{"id":"quiet","name":"Quiet Novels","site":"http://{host}/site/","lang":"English","version":"1.0.0",' \
                    f'"url":"http://{host}/lnreader/quiet[test].js","iconUrl":"http://{host}/pages/2"}}]'
            return self.reply(index.encode(), "application/json")
        if path in ("/lnreader/quiet[test].js", "/lnreader/quiet%5Btest%5D.js"):
            return self.reply(PLUGIN.replace("SITE", f"http://{host}/site/").encode(), "application/javascript")
        if path.startswith("/site/") and path[len("/site/"):] in SITE:
            return self.reply(SITE[path[len("/site/"):]].encode(), "text/html; charset=utf-8")
        if path.startswith("/pages/"):
            return self.reply(page(int(path.rsplit("/", 1)[1])), "image/png")
        if path.startswith("/suwayomi/api/v1/page/"):
            if self.headers.get("Authorization") != AUTH:
                self.send_response(401)
                self.end_headers()
                return
            return self.reply(page(int(path.rsplit("/", 1)[1])), "image/png")
        if self.headers.get("Authorization") != AUTH:
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Basic realm="test"')
            self.end_headers()
            return
        if path == "/opds/catalog":
            self.reply(CATALOG.encode(), ATOM)
        elif path == "/opds/all":
            self.reply(books("All books").encode(), ATOM)
        elif path == "/opds/search.xml":
            # A relative template is not in the standard, so the server gives an absolute one.
            host = self.headers.get("Host")
            self.reply(SEARCH.replace("/opds/find", f"http://{host}/opds/find").encode(), "application/opensearchdescription+xml")
        elif path == "/opds/find":
            self.reply(books("Results").encode(), ATOM)
        elif path == "/files/sunrise.cbz":
            self.reply(cbz(), "application/vnd.comicbook+zip")
        else:
            self.send_response(404)
            self.end_headers()

    def reply(self, body, kind):
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    print(f"http://127.0.0.1:{port}/opds/catalog", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
