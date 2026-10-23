<div align="center">
  <a href="README.md"><img src="assets/brand/icon-512.png" alt="Asabunko" height="44"></a>
</div>

# Changelog

Every release is written here, newest first. A version is `MAJOR.MINOR.PATCH`.
Each release before 1.0.0 adds one large function. See "Version numbers" in
the decisions.

A tag such as `v0.1.0` builds the unsigned IPA and attaches it to a release on
GitHub as `Asabunko.ipa`.

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
