#!/usr/bin/env python3
"""A small server for the UI tests of the sources.

Under /opds/, it asks for the user "asa" with the password "morning". It
serves a catalog, an OpenSearch search, one comic as a CBZ, and the pages of
the comic one at a time with the Page Streaming Extension.

Under /lnreader/, it serves a list of LNReader plugins with one plugin, and
under /site/ the web site that the plugin reads.

It makes each file in memory.

Usage: python3 scripts/test-server.py [port]
"""
import base64
import io
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
var Quiet = (function () {
  function Quiet() { this.id = "quiet"; this.name = "Quiet Novels"; this.site = "SITE"; this.version = "1.0.0"; }
  Quiet.prototype.popularNovels = async function (page, options) {
    var $ = (0, cheerio_1.load)(await (0, fetch_1.fetchText)(this.site + "list?page=" + page));
    return $(".novel a").map(function (i, el) { return { name: $(el).text(), path: $(el).attr("href"), cover: $(el).attr("data-cover") }; }).get();
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

SITE = {
    "list": '<div class="novel"><a href="novel/dawn" data-cover="/pages/1">Dawn Tea</a></div>',
    "novel/dawn": '<h1>Dawn Tea</h1><span class="author">Mina</span><p class="summary">A shop opens at dawn.</p>'
                  '<ul><li class="chapter"><a href="novel/dawn/1">First Cup</a></li><li class="chapter"><a href="novel/dawn/2">Second Cup</a></li></ul>',
    "novel/dawn/1": '<div id="content"><p>The kettle sang in the small shop.</p></div>',
    "novel/dawn/2": '<div id="content"><p>Rain came in the afternoon.</p></div>',
}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?")[0]
        host = self.headers.get("Host")
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
