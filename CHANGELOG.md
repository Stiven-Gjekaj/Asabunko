<div align="center">
  <a href="README.md"><img src="assets/brand/icon-512.png" alt="Asabunko" height="44"></a>
</div>

# Changelog

Every release is written here, newest first. A version is `MAJOR.MINOR.PATCH`.
Each release before 1.0.0 adds one large function. See "Version numbers" in
the decisions.

A tag such as `v0.1.0` builds the unsigned IPA and attaches it to a release on
GitHub as `Asabunko.ipa`.

## 1.2.0 (not released)

- Search asks all your sources at the same time, as in ZettaStream. A title
  that many sources have shows one time, with the number of its sources.
  The search keeps your recent searches.
- The page of a title compares its sources and shows the source with the
  most chapters. The Source menu lists each source with its number of
  chapters, so you can choose another one. A chapter that two groups
  translated counts one time.
- Show the chapters by volume. A series with more than 50 chapters shows
  them in ranges, such as 1-50 and 51-100.
- A new Discover tab, after the library: a banner of popular titles with
  their art, and rows of popular comics, popular novels, and new chapters.
- The library has Continue reading and the read list. Tap the bookmark on
  the page of a title to put it in the read list. A title that you only open
  shows in Continue reading.
- The sources moved from the Browse tab to Settings, Sources. Save installs
  the sources of each new list in the languages of the device. A removed
  line removes its sources.
- Empty screens show art: a fan of covers on a soft glow.

## 1.1.0 (2026-10-23)

- Download the chapters of an online comic or novel, to read with no
  network. The Downloads menu of a series has "Download all chapters",
  "Download from this chapter", and "Remove downloads". The library menu of
  a book has them too.
- Each chapter shows a mark: downloaded, waiting, or the progress of the
  download.
- A downloaded chapter opens from the device first.

## 1.0.1 (2026-10-23)

- A new app icon: the mark of the logo of the banner. It fills the full
  width of the icon, so no black bar shows at the sides.
- The empty shelf shows the same mark.
- The app builds with Xcode 26.6, the Xcode of the release builds on GitHub.

## 1.0.0 (2026-10-23)

- The first full version. It has all functions of 0.1.0 to 0.8.0: comic
  archives, EPUB, TXT, FB2, HTML, PDF, OPDS catalogs, LNReader plugins,
  Suwayomi servers, Aidoku sources, and Paperback extensions.
- Adds a backup in Settings. Save a backup keeps your books, your places,
  your sources, and the chapters of your online books in one file. Restore a
  backup puts it in the place of your library. The code of your installed
  sources downloads again. The app tells you which books from files to
  import again.
- The refresh button of the library checks each online book for new
  chapters, and tells you how many it found.
- The accent of the dark look is a lighter red, so that text in it is easy
  to read on each surface.
- The Add sources row and the Sources button are easier to tap.

## 0.8.0 (2026-10-23)

- Adds Paperback 0.9 extensions. Paste the URL of a repository, such as
  https://inkdex.github.io/extensions/0.9/stable, into Sources.
- Open the repository, and install the extensions that you want. A tracker,
  such as AniList, is not in the list, because it does not give chapters.
- Each extension shows its popular and latest series from its discover
  sections, and you can search it.
- The interceptors of an extension run for each request and for each page,
  so the referer and the cookies that a site asks for go with them.
- The state of an extension stays, with its cookies and its settings.
- An extension that says that a series is a novel adds it to the library as
  a novel.
- A site that shows a Cloudflare challenge does not work yet.

## 0.7.0 (2026-10-23)

- Adds Aidoku sources. Paste the URL of a list of Aidoku sources, such as
  https://aidoku-community.github.io/sources/index.min.json, into Sources.
- Open the list, and install the sources that you want. Each source is a
  WebAssembly module that runs on the device.
- Each source shows its popular and latest series, when it has those lists,
  and you can search it.
- Add a series to the library, or open a chapter to read it. The pages come
  from the site of the source, with the headers that the source asks for.
- The Aidoku sources of novels give their chapters as text, which opens in
  the reader of novels.
- A source that needs a web view or that draws its pages again does not
  work yet.

## 0.6.0 (2026-10-23)

- Adds Suwayomi servers, which run the extensions of Mihon on a computer.
  Paste the URL of the server, such as http://192.168.1.20:4567, into
  Sources. For a server with an account, write
  http://user:password@host:4567.
- Open the server, and show the sources that you want. Each source has its
  popular and latest series, and its search.
- Add a series to the library, or open a chapter to add it and read it. The
  pages come from the server.
- At the last page of a chapter, the buttons go to the previous chapter,
  the list of chapters, and the next chapter.
- Settings has a switch for the sources that a list marks for adults. They
  stay hidden until you turn it on.

## 0.5.0 (2026-10-23)

- Adds web novels with LNReader plugins. Paste the URL of a list of
  plugins, such as the plugins.min.json of LNReader, into Sources.
- Open the list, and install the plugins that you want. The plugins of each
  language are together.
- Each installed plugin shows its popular and latest novels, and you can
  search it.
- The page of a novel has its author, its summary, its genres, and its
  chapters, from the oldest or from the newest.
- Add a novel to the library, or open a chapter to add it and read it. A
  chapter downloads the first time it opens, and the next chapter downloads
  with it. A chapter that downloaded stays for reading with no network.
- The page of a novel that is in the library adds its new chapters.

## 0.4.0 (2026-10-23)

- Adds sources, with the paste box of ZettaStream. Open Browse, tap Sources,
  and paste one URL on each line. Save replaces the list.
- Asabunko finds the kind of each source from its URL, or from what it gives.
- Adds OPDS catalogs: Komga, Kavita, Calibre-web, Suwayomi, and other
  servers, in OPDS 1.2 and OPDS 2.0.
- For a server with an account, write https://user:password@host/... The
  password goes to the Keychain, and the list shows only the user name and
  the host.
- Browse the catalog, search it, and load more books.
- Read a comic now, page by page from the server, or download a book into
  the library.
- The app has three tabs: Library, Browse, and Settings.

## 0.3.0 (2026-10-23)

- Adds PDF. Import a PDF from Files or with "Open in Asabunko". The title and
  the author come from the PDF, and the cover from its first page.
- Read a PDF page by page from the left or from the right, or in one
  vertical column. Pinch to zoom. The page stays.
- A PDF with a password does not import, and the app tells you why.

## 0.2.0 (2026-10-23)

- Adds novels. Import EPUB 2 and EPUB 3 books, TXT files, FB2 books, and HTML
  pages from Files or with "Open in Asabunko".
- The chapters come from the spine of an EPUB, with their titles from the
  table of contents. A TXT file gets a chapter at each heading, such as
  "Chapter 12" or "第十二章", and a long text with no headings gets parts.
- A TXT file can be in UTF-8, UTF-16, Shift JIS, GB18030, or Windows-1252.
- Read one chapter at a time, with a list of the chapters and buttons for the
  next and the previous chapter. The place in each chapter stays.
- Choose a serif font, a sans serif font, or Karla, and the size, the line
  spacing, the margins, and justified text.
- The scripts of a book do not run.
- An EPUB with DRM does not import, and the app tells you why.
- The new logo is the app icon, and its red is the accent of the app.

## 0.1.0 (2026-10-23)

- The first release: the library and the comic reader.
- Import CBZ, CBR, CB7, and CBT files, ZIP, RAR, 7z, and TAR archives, and
  folders of images from Files. "Open in Asabunko" from another app also
  imports the file.
- The title, the writer, and the direction come from ComicInfo.xml.
- Read page by page from the right to the left or from the left to the
  right, or in one vertical column for a webtoon. Pinch or double tap to zoom.
- The library shows the books to continue, with the page and the progress.
- Mark a book as read or as unread, and delete a book.
- Choose "Warm dark", "Paper", or the look of the device.
- The app tells you when a newer version is available.
