<div align="center">
  <a href="../README.md"><img src="../assets/brand/icon-512.png" alt="Asabunko" height="44"></a>
</div>

# Decisions

Each choice of the owner is written here, with its reason. A new choice that
replaces an old one names the old one.

## 2026-10-23: A universal reader for iOS

- Asabunko reads manga, comics, and light novels and web novels on iPhone
  and iPad. The lowest version is iOS 17.
- "Asa" is the morning and "bunko" is a small paperback library in Japanese.
- A visual novel here is a light novel or a web novel: text with images. The
  app does not play visual novel games, such as Ren'Py games.
- The app reads each format that is well known, in the files of the user and
  from the source ecosystems of the community.
- Reason: the owner asked for one app for all of these formats.

## 2026-10-23: Native Swift, with a core package

- The app is native Swift with SwiftUI.
- XcodeGen makes the Xcode project from `project.yml`. The generated project
  is not in the repository.
- The parts that do not need a screen are in the Swift package `AsaCore`.
  They build and test on a Mac with `swift test`, with no simulator.
- Reason: the same form as Polytechnium and ZettaStream for iOS. The tests
  run in seconds.

## 2026-10-23: An unsigned IPA for sideloading

- The app is not in the App Store.
- A tag such as `v0.1.0` builds an unsigned `Asabunko.ipa` and attaches it to
  a release on GitHub. The SideStore source of the owner shows each release.
- Reason: the same plan as Polytechnium. The App Store does not take an app
  that reads from community sources.

## 2026-10-23: The archives open with the libarchive of the system

- The SDK of iOS has libarchive, but not its headers. `AsaCore/Sources/CArchive/shim.h`
  declares the functions that the app uses.
- libarchive reads ZIP, RAR, RAR5, 7z, and TAR. So the app reads CBZ, CBR,
  CB7, and CBT with no library from another party.
- Reason: the app stays small and has no code under the GPL or the license of
  unrar. The App Store does not take an app that links a library with no
  public headers, but a sideloaded app can.

## 2026-10-23: The pages of a comic are copied at the import

- The import copies each image of the archive or the folder into a folder of
  the book, with the names 0001.jpg, 0002.png, and so on, in the natural
  order of their paths. The app does not keep the archive.
- A file of macOS, such as `__MACOSX/` or `._page.jpg`, is not a page. A path
  with a ".." part is not a page.
- The app never uses a name from an archive as a path.
- Reason: a page opens with no work on the archive, also for a solid RAR or
  7z, where one page needs the pages before it. A name in an archive can
  point out of the folder.

## 2026-10-23: ComicInfo.xml

- The import reads ComicInfo.xml, the format of ComicRack, when the archive
  or the folder has it. The title is "Series Number: Title".
- "Manga" with the value "YesAndRightToLeft" opens the book from the right to
  the left. The value "Yes" does not change the direction.
- Reason: this is the metadata that Komga, Kavita, Mihon, and ComicTagger
  write.

## 2026-10-23: The reading modes

- The modes are left to right, right to left, and vertical scroll.
- The library has one mode. A book can have its own mode, which the user
  chooses in the reader. The mode of the library is right to left at the
  start.
- A tap at the left or the right third of the screen turns the page. In a
  manga, the left edge goes forward. A tap in the middle shows or hides the
  bars.
- Reason: most of the content is manga. A western comic and a webtoon need
  the other two modes.

## 2026-10-23: The look

- The theme comes from ZettaStream: the layout, the Karla font, the cards,
  and few colours. It is more comforting than ZettaStream.
- The dark form is warm charcoal, not black. The light form is paper, a
  cream colour. The accent is apricot in the dark form and terracotta on
  paper.
- The corners have a radius of 14 points in place of 8. The covers have a
  soft shadow.
- The user chooses "Same as the device", "Warm dark", or "Paper" in Settings.
- Reason: the owner asked for the ZettaStream theme, more comforting and not
  so minimal, with a warm dark form and a paper form.

## 2026-10-23: One language

- The text of the app is in English.
- Reason: the readers of the sources are in many countries. A second language
  can come later with the form of Polytechnium.

## 2026-10-23: The data on the device

- The library is one JSON file in the Application Support folder. The pages
  are in a folder for each book next to it.
- The file has a form number. An app reads an older form, and does not read a
  newer form.
- The app has no account, no server, and no analytics.
- Reason: a file is easy to examine and to back up.

## 2026-10-23: The sources of the community

The research of 2026-10-23 found these facts:

- Aidoku sources are WebAssembly. Their list is
  `https://aidoku-community.github.io/sources/index.min.json`. The interface
  is published by aidoku-rs under the MIT License. AidokuRunner, the host of
  the Aidoku app, is not open source.
- Paperback 0.9 extensions are JavaScript bundles with a `versioning.json`.
  JavaScriptCore can run them.
- LNReader plugins are JavaScript for novels, under the MIT License, with a
  list of about 320 plugins. JavaScriptCore can run them.
- Mihon extensions are Android APK files. iOS cannot run them. A Suwayomi
  server runs them and gives a GraphQL API.
- Komga, Kavita, Calibre-web, and Suwayomi give OPDS 1.2. Komga also gives
  OPDS 2.0.

The choices:

- The app has its own host for each ecosystem. It does not copy code from the
  Aidoku app, Paperback, or AidokuRunner.
- The app does not have a source in it. The user adds the URL of a list.
- Reason: the owner asked for a universal app. Each of these ecosystems can
  run on iOS, except Mihon, which runs through Suwayomi.

## 2026-10-23: Version numbers

- The versions start at 0.1.0. Each release before 1.0.0 adds one large
  function:
  - 0.1.0 the library and the comic archives
  - 0.2.0 EPUB and text novels
  - 0.3.0 PDF
  - 0.4.0 OPDS servers
  - 0.5.0 LNReader plugins, for novels on the web
  - 0.6.0 Aidoku sources
  - 0.7.0 Paperback 0.9 extensions
  - 0.8.0 Suwayomi servers, for Mihon extensions
- 1.0.0 has all of these functions, with a backup of the library.
- From 1.0.0, a fix raises the patch number, a new function raises the minor
  number, and a change that an older version cannot read raises the major
  number.
- Reason: the same plan as Polytechnium. The files of the user come first,
  so the app is useful before it reads a source.

## 2026-10-23: The logo of the owner

- The owner gave the logo: a girl who reads a manga, with a red morning sun
  behind her and the word "asabunko" under her.
- The app icon is the mark with no word, on a dark ink background. The
  empty shelf shows the mark.
- The README shows the full logo as its banner.
- The accent of the app is the red of the logo, `#FF5866` in the dark form
  and `#C42F45` on paper. This replaces the apricot and the terracotta of
  "The look". The background, the paper, and the corners do not change.
- Reason: the owner asked for the logo in the app and on GitHub. One red in
  the icon and in the app makes one brand.

## 2026-10-23: The novels

- An EPUB, a TXT, an FB2, and an HTML file become a novel: a folder with the
  files of the chapters and `novel.json`, which lists the chapters with their
  titles. One reader shows each of them.
- An EPUB keeps all of its files in content/. Its chapters are the items of
  its spine, with the titles of its nav or its NCX.
- A TXT file gets a chapter at each line such as "Chapter 12", "Prologue",
  or "第十二章", when it has two such lines or more. Else a long text gets
  parts of about 60000 characters.
- A TXT file that is not UTF-8 is read as Shift JIS when it gives kana, as
  GB18030 when many of its bytes are above 0x7F, or as Windows-1252.
- An EPUB with an encrypted chapter does not import. The app reads only books
  with no DRM.
- Reason: the web novels and the light novels of the owner come as EPUB and
  TXT. FB2 is common for Russian books. One form of chapter lets the novels of
  the web sources use the same reader later.

## 2026-10-23: The reader of novels

- A chapter shows in a web view, from the top to the bottom. The app keeps
  the chapter and the place in it, from 0 to 1.
- The scripts of the book do not run. The scripts of the app run in their own
  world. They apply the style, give a viewport, keep the place, and report a
  tap.
- The style of the app goes over the style of the book: the colours of the
  look, a serif font, a sans serif font, or Karla, the size, the line
  spacing, the margins, and justified text.
- A link to a chapter opens that chapter. A link to the web opens in Safari.
- Reason: a scroll is the same on a phone and a tablet, and a chapter of a
  web novel is one long page. A book can hold a script, which must not run
  with the files of the app.

## 2026-10-23: The form of the library before 1.0.0

- The library stays in form 1 up to 1.0.0. A new field gets its first value
  when an older file does not have it.
- Reason: there is no backup before 1.0.0, so an older version of the app
  never reads a newer file. 1.0.0 writes the form that the backup uses.

## 2026-10-23: The PDF

- The import copies the PDF into the folder of the book as `book.pdf`. The
  cover is its first page, drawn on white.
- A PDF opens in the reader of pages, with PDFKit. The three modes are the
  modes of the comics. The mode of a PDF is left to right at the start.
- A PDF that needs a password does not import.
- Reason: a PDF keeps its own pages, so the app does not change them. Most
  PDFs are western documents and scans.

## 2026-10-23: The square logo and a softer red

- The app icon is the square logo of the owner, with no word. Its red is
  softer: each red pixel loses 18 percent of its saturation and 10 percent
  of its brightness. `assets/brand/render.swift` makes this change.
- The accent of the app is the new red, `#E34659` in the dark form and
  `#B8303F` on paper. This replaces the reds of "The logo of the owner".
- Reason: the owner gave a square logo for the icon and asked for a softer
  red.

## 2026-10-23: The source list is a paste box

- The source list is text, one URL on each line, as in ZettaStream. Save
  replaces the full list. The Paste button of the system reads the
  clipboard with no prompt.
- Asabunko finds the kind of each line from its URL: "/opds" is a catalog,
  "plugins.min.json" is LNReader, "index.min.json" is Aidoku,
  "versioning.json" is Paperback, and the port 4567 is Suwayomi. When the URL
  does not tell, the app reads the URL and finds the kind from its content.
- "https://user:password@host/..." gives a user name and a password. The
  password goes to the Keychain of the device. The list shows the user name
  and no password. A line with the same URL and user name keeps its
  password.
- The app sends the password only to the host of its source.
- Reason: the owner asked for the paste box of ZettaStream. The form with a
  password field also made iOS ask to save the password.

## 2026-10-23: The OPDS catalogs

- The app reads OPDS 1.2, in Atom, and OPDS 2.0, in JSON. It follows the
  navigation links, the groups, the next pages, and the search of OpenSearch
  or of a URL template.
- A book can stream with the Page Streaming Extension, page by page, or
  download into the library. The download takes the first file that the app
  can import.
- A page from the network stays in the caches folder of the app.
- The app can open http:// servers, because a server at home often has no
  certificate. The user chooses each server.
- Reason: Komga, Kavita, Calibre-web, and Suwayomi give OPDS. It is the most
  common way to read a library of your own.

## 2026-10-23: The JavaScript sources

- LNReader plugins and Paperback extensions are JavaScript. They run in
  JavaScriptCore, one context for each source, on its own queue.
- The app gives the functions of a browser that the sources use: fetch,
  Headers, Response, FormData, timers, TextDecoder in each encoding of iOS,
  atob and btoa, URL, and URLSearchParams. URLSession makes the requests.
- `js/libraries.js` bundles cheerio, htmlparser2, dayjs, the AES of
  @noble/ciphers, and the URL functions of core-js. `scripts/build-js.sh`
  makes the bundle with esbuild. The bundle is in the repository, so a build
  of the app does not need Node.
- A call into a source has a limit of 60 seconds.
- Reason: JavaScriptCore is in iOS, and these libraries are what the plugins
  ask for with require().

## 2026-10-23: The LNReader plugins

- A line with "plugins.min.json" is a list of LNReader plugins. The user
  installs the plugins that they want. The app keeps the code of each one in
  the folder of the library.
- The app gives the modules of the LNReader app to a plugin: cheerio,
  htmlparser2, dayjs, urlencode, and the @libs modules. fetchProto is not
  there, so the few plugins that need protobuf do not work.
- The storage of a plugin stays only while the app runs.
- Reason: the plugins are under the MIT License and need only these
  modules. The protobuf library is large, and only a few plugins use it.

## 2026-10-23: An online book in the library

- A novel or a series of a source goes into the library as a book with its
  origin: the line of the source list, the source, and the series.
- Its folder has `novel.json`, with each chapter of the source in order. A
  chapter of a novel downloads into its file the first time it opens. The
  reader then downloads the next chapter too.
- The page of the series adds the new chapters. A chapter that the source
  removes stays in the book.
- To read a chapter adds the series to the library, so that the place stays.
- Reason: one form of book lets the novels of the web use the reader of
  novels, with no network after the download.

## 2026-10-23: iOS 18

- The lowest version is iOS 18. This replaces iOS 17 of "A universal reader
  for iOS".
- Reason: WasmKit, the WebAssembly runtime of the Aidoku sources, needs iOS
  18 from version 0.3.0. iOS 18 runs on the same iPhones and iPads as iOS 17,
  from the iPhone XS, so no device is lost.

## 2026-10-23: The order of the releases of the sources

- 0.6.0 is Suwayomi, 0.7.0 is Aidoku, and 0.8.0 is Paperback. This replaces
  the order of "Version numbers", which had Aidoku, Paperback, and then
  Suwayomi.
- Reason: the client of Suwayomi was ready first. Each release still adds one
  large function.

## 2026-10-23: The Suwayomi servers

- A line with "suwayomi", "tachidesk", or the port 4567 is a Suwayomi server.
  The app sends GraphQL to /api/graphql.
- The sources of the server are the sources of its extensions. The local
  source of the server is not there. The user shows the sources that they
  want, with no download, because they run on the server.
- The password of the line goes to the server for each request and for each
  page of the server, and not to another host.
- The chapters come from the oldest to the newest, in the reverse of the
  order of the source.
- Reason: Mihon extensions are Android code, which iOS cannot run. A Suwayomi
  server runs them and gives them to the app.

## 2026-10-23: The sources for adults

- A list can mark a source for adults. The app hides these sources until the
  user turns on "Show sources for adults" in Settings.
- Reason: a calm default. The user decides.

## 2026-10-23: The Aidoku sources

- A line with "index.min.json" or "aidoku" is a list of Aidoku sources. Each
  source is an .aix package: a ZIP with Payload/main.wasm and
  Payload/source.json. The app keeps the package of each source that the user
  installs.
- The sources run in WasmKit, a WebAssembly interpreter in Swift, one
  instance for each source, on its own queue. The imports of the network
  wait for the answer on that queue.
- The host follows the new interface of aidoku-rs, under the MIT License:
  the env, std, net, html, and defaults imports, the postcard data, and the
  result buffers of the exports. The html imports use SwiftSoup, which has
  the behaviour of jsoup that the sources expect.
- The app reads the imports of each module. An import that the host does not
  have, such as js or canvas, gets a stub of the same type that gives an
  error. So a source that needs a web view or that draws its pages again
  fails with a message, and the other sources load.
- The app does not use AidokuRunner, the host of the Aidoku app, because it
  is not open source.
- The popular list is a listing with a name such as "popular" or "hot". The
  latest list is a listing with a name such as "latest" or "update". With no
  such listing, the popular list is a search with no words.
- A source with "novel" in its name is a source of novels. Its text, in
  Markdown, becomes the HTML of a chapter.
- Reason: Aidoku Community has about 140 sources for iOS, and the interface
  of aidoku-rs is published under the MIT License.

## 2026-10-23: The Paperback extensions

- A line with "versioning.json", "paperback", or "inkdex" is a repository of
  Paperback 0.9 extensions. The URL can be the folder or its
  versioning.json. Each extension is <Id>/index.js. An extension with no
  chapters or no search, such as a tracker, is not in the list.
- Each extension runs in its own JavaScript context. The prelude
  `paperback.js` gives the Application global of the types of the Paperback
  toolchain, under the MIT License: selectors, interceptors,
  scheduleRequest, state, and the functions for text, Base64, and MD5.
- Each interceptor gets the request that the one before it gave. The
  answers go back through the interceptors in the reverse order.
- The state is JSON with a tag for each Date, because the cookie store of the
  extensions keeps dates. It stays in a file next to the code.
- crypto.subtle has the digests, AES-CBC, and AES-GCM, with CryptoKit and
  CommonCrypto in Swift.
- The pages and the covers get the headers of the request interceptors. The
  response interceptors do not run on the images.
- executeInWebView and the Cloudflare challenge are not there yet.
- Reason: the Paperback app is not open source, but the types and the
  toolchain are. Inkdex has 68 extensions for version 0.9.

## 2026-10-23: The contrast of the accent

- The accent in the dark form is `#EE6271`, a lighter form of the red of the
  logo. This replaces `#E34659` of "The square logo and a softer red" for the
  accent. The icon keeps `#E34659`.
- The contrast of each text colour on each background, by WCAG 2:
  - paper: the text 12.5 or more, the grey text 5.2 or more, the accent 4.8
    or more, and the text on the accent 5.6.
  - warm dark: the text 12.7 or more, the grey text 5.6 or more, the accent
    4.8 or more, and the text on the accent 6.0.
- The accessibility audit of the UI tests counts a contrast finding and a
  clipped text as notes, as in ZettaStream. Each other finding fails the test.
- Reason: `#E34659` had a contrast of 3.8 on the cards of the dark form, which
  is less than the 4.5 of WCAG AA.

## 2026-10-23: The backup

- The backup is one JSON file: the library with the places, the source list
  with no passwords, the installed sources, and the chapters of each online
  book. It does not hold the files of the books.
- A restore puts the backup in the place of the library. An online book
  comes back with its chapters, which download again. A book from a file
  comes back only when its files are on the device. The app names the other
  books, so that the user imports them again.
- The code of each installed source downloads again after a restore.
- A backup has a form number. A backup of a newer form does not restore.
- Reason: the data stays on the device, so the user needs a way to move it
  to a new phone. The files of the books can be large, and the user has them.

## 2026-10-23: What 1.0.0 has

- 1.0.0 has the functions of 0.1.0 to 0.8.0, with the backup and the check
  for new chapters.
- The checks of 1.0.0: 95 unit tests of the core package, in a debug and a
  release build, and the UI tests of the simulator. The UI tests import and
  read a manga, an EPUB, and a PDF, change the look, run the accessibility
  audit, and use each kind of source with the test server of the scripts.
  Three live unit tests read five real LNReader, Aidoku, and Paperback sources from
  the web with `ASABUNKO_LIVE=1`.
- The checks that need a real iPhone are in the roadmap.
- Reason: the owner asked for the full app up to 1.0.0.

## 2026-10-23: The icon from the banner

- The app icon is the mark of the banner, `logo-full.png`, with no word. This
  replaces the square logo of "The square logo and a softer red".
- The mark is taller than it is wide. It fills the width of the icon, and
  about 3 percent of its height goes out at the top and at the bottom. So no
  black bar shows at the sides.
- The red of the icon is the red of the banner, `#FF5866`. The accent of the
  app does not change.
- Reason: the owner asked for the mark of the banner as the icon, with no
  bars at the sides.

## 2026-10-23: Chapters on the device

- A download writes the pages of a chapter to a `.part` folder. The folder
  gets its final name and a `.complete` mark only when all pages are there.
  So a stopped download never looks complete.
- Each page has three attempts. One queue downloads one chapter at a time.
- The reader opens the files of a downloaded chapter before it asks the
  source.
- The roadmap has no check with a real OPDS or Suwayomi server. The owner
  does not use a server.
- Reason: the owner asked for the roadmap tasks that need no work from the
  owner.

## 2026-10-23: Search, Discover, and the read list

- The app finds titles as ZettaStream does. Search asks all installed
  sources, and Discover shows their popular titles. The Browse tab of the
  sources is gone. The sources are in Settings, Sources.
- Search joins the titles of many sources by a key: the letters and the
  digits of the title in lowercase, with no accents. The same title comes
  first, then the title that more sources have.
- The page of a title asks each source of the title at the same time. The
  source with the most different chapter numbers wins. A source that lists a
  chapter once for each group gives a high count of chapters, but not more
  chapters.
- The source of a book in the library always wins, so that the place of the
  user stays.
- Save installs all sources of a list in the languages of the device, and
  the sources for all languages. Adult sources stay out until the user turns
  them on. Four sources install at the same time.
- A book has a `listed` mark. The read list holds the listed books. A title
  that the user only opens is in the library to keep the place, but not in
  the read list. A book of an older version is listed.
- The volume of a chapter comes from its title, such as "Vol. 2 Ch. 10".
  Aidoku and Paperback put the volume number in the title.
- Discover asks at most 10 sources, so that it opens fast.
- Reason: the owner asked for search, Discover, and the read list as in
  ZettaStream, with no install button, and with volumes and ranges.

## 2026-10-23: Kindle books

- The importer reads the PalmDB records itself. No library on iOS reads
  MOBI, and the format is small: PalmDOC compression, the trailing entries
  of each text record, and the EXTH facts.
- A KF8 book keeps its text as skeletons and fragments. The importer reads
  the SKEL and FRAG indexes and puts each fragment into its skeleton, as
  calibre does. Each skeleton is one chapter.
- A joint file has a MOBI 6 part and a KF8 part. The importer reads the KF8
  part, because it keeps the styles.
- Links to a place in the full text, such as `filepos` and `kindle:pos`, go.
  The chapter list does the same work.
- The HUFF/CDIC compression and DRM stop the import with a message. Only
  books of the Kindle store use them.
- The checks: unit tests that build MOBI bytes, a UI test that imports a
  MOBI, and a live test with the AZW3 and MOBI files of Project Gutenberg.

## 2026-10-23: Filters and settings of the sources

- One model holds the filters and the settings of all kinds of source: a
  text, a switch, one choice, many choices with an optional exclude, and a
  sort with an optional ascending order.
- Aidoku: the filters come from `filters.json` of the package, and the
  settings from `settings.json`. A search sends the values as postcard
  `FilterValue` items. A setting goes into the defaults of the source in the
  form that aidoku-rs reads. The dynamic filters of `get_filters` do not show
  yet. The sources of Aidoku Community use the static file.
- LNReader: the filters come from `plugin.filters`, and the list gets the
  values in `popularNovels`. The settings come from `pluginSettings`. The
  values go into the storage of the plugin and into a file next to its code.
  A search of LNReader has no filters.
- Paperback: the filters come from `getSearchFilters`, and the search gets
  them in its query. The settings of Paperback are forms with their own
  layout, so they do not show.
- Suwayomi gives no filters or settings yet.
