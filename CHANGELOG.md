<div align="center">
  <a href="README.md"><img src="assets/brand/icon-512.png" alt="Asabunko" height="44"></a>
</div>

# Changelog

Every release is written here, newest first. A version is `MAJOR.MINOR.PATCH`.
Each release before 1.0.0 adds one large function. See "Version numbers" in
the decisions.

A tag such as `v0.1.0` builds the unsigned IPA and attaches it to a release on
GitHub as `Asabunko.ipa`.

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
