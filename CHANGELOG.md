<div align="center">
  <a href="README.md"><img src="assets/brand/icon-512.png" alt="Asabunko" height="44"></a>
</div>

# Changelog

Every release is written here, newest first. A version is `MAJOR.MINOR.PATCH`.
Each release before 1.0.0 adds one large function. See "Version numbers" in
the decisions.

A tag such as `v0.1.0` builds the unsigned IPA and attaches it to a release on
GitHub as `Asabunko.ipa`.

## 2.8.0 (2026-10-24)

Asabunko fits into iOS.

- The app is in Japanese on a device in Japanese.
- A Home Screen widget shows the books of Continue reading with their
  covers. A tap opens the book.
- Hold a book that you imported and choose "Share the file". A comic goes
  out as a CBZ, a PDF as a PDF, and a novel from an EPUB as an EPUB. Save it
  to Files, or send it to another app.
- Asabunko is in the "Open in" list for HTML files too.
- The device taps lightly at the end of a chapter of a novel, and when a
  turn stops at the last page of a comic.
- On an iPad, or on a phone that you turn, a page that fits the screen stays
  in the middle after the turn.

## 2.7.0 (2026-10-24)

Your progress goes to your trackers and your servers.

- Sign in to AniList or MyAnimeList in Settings, Trackers. Asabunko has no
  client on these sites, so you register a client with the redirect URI
  that the page shows, and paste its ID.
- Hold a book in the Library and choose Track. The app searches the tracker
  with the title of the book, and you choose the entry.
- Each time the number of chapters that you read goes up, the tracker gets
  it. A finished book is complete on the tracker. Private reading sends
  nothing.
- A comic that you read from a Komga or Kavita catalog opens at the last
  page that the server keeps. Each new page goes back to Komga. Kavita keeps
  the page when it gives it to the app.

## 2.6.0 (2026-10-23)

The reader does more.

- On a wide screen, such as an iPad or a phone in landscape, a comic shows
  two pages side by side. The cover stays alone. "Move the pairs by one
  page" fixes a book whose pairs are wrong. A wide page stays alone.
- The new Page layout menu of the reader chooses the fit of a page: the
  screen, the width, or the height. "Crop the borders" removes the plain
  borders of each page.
- The same menu chooses the taps at the edges: left and right, forward at
  each edge, or no turns.
- A novel can read itself aloud, one sentence at a time, with the voice of
  the device.
- Search the words of a novel, in all of its chapters.
- Keep bookmarks in a novel, and keep highlights: select words, then choose
  Highlight. The Marks list opens each one at its place.

## 2.5.0 (2026-10-23)

The library has more tools.

- Put the books of the read list in categories. Tap "Add a category" above
  the read list, and hold a book to choose its categories.
- Search the library by title or author. Filter the read list to show only
  the unread books, the books on the device, the comics, or the novels.
- The Library has a History of the chapters and the books that you opened,
  the newest first. Remove one entry, or clear all of it.
- With "Private reading" on in Settings, the books that you read do not go
  into the history or into Continue reading.
- A book now goes into Continue reading when you open it, not only when you
  turn a page.
- Settings has a Storage page. It shows the downloads of each book and
  their size, and removes all of them or only the chapters that you read.
- "Move books to another source" in Settings moves many books at one time.
  The app finds each title in the new source, and you see the matches
  before the move.

## 2.4.0 (2026-10-23)

New chapters come to you.

- The books of your read list can check for new chapters in the
  background. Turn on "Check in the background" in Settings. iOS chooses the
  time of each check.
- A notification tells you about the new chapters of a book. A tap on it
  opens the book.
- The Library has an Updates list with the new chapters of all books, the
  newest first.
- A book with "Download new chapters" on downloads each new chapter after
  a check. "Download only on Wi-Fi" in Settings keeps the downloads off
  other networks.

## 2.3.0 (2026-10-23)

The gaps of the sources are closed.

- Aidoku sources show their range filters, such as the release year of
  MangaFire, as two number fields.
- Aidoku sources show all their settings in one form: groups, pages, lists
  of choices, lists that you edit, buttons, links, and steppers.
- You can sign in to an Aidoku source with a user name and a password, in
  a web page, or with OAuth. You can sign out again.
- Paperback extensions can sign in with OAuth, such as MangaDex.
- Paperback extensions that run a page in a web view work, such as
  MangaFire.
- Suwayomi sources show their filters and their settings. A change of a
  setting goes to the server.
- LNReader plugins with a filter for the words of a search, such as
  WTR-LAB and NovelBuddy, search with the other filters too.

Fixes:

- The vertical reader does not jump when you scroll fast. Each strip has
  its height before its image comes, and the next strips load before you
  get to them.
- Each save of the source list installs the English sources that are not on
  the device, and removes the sources of the lines that you removed. The
  other sources do not download again.
- The filter sheet keeps the choices of a list of choices when the list
  closes.

## 2.2.0 (2026-10-23)

- Paperback extensions show their settings, such as the languages and the
  content filters of MangaDex. The gear on the screen of the source opens
  the form of the extension, with its sections, switches, text fields,
  buttons, and lists of choices. A form that has a Save button keeps its
  changes only when you tap Save.
- A sign-in with OAuth shows in the form, but Asabunko cannot do it yet.

## 2.1.0 (2026-10-23)

- Aidoku sources that make their filters in code show them too, after the
  filters of their package, such as Kagane and CopyManga.
- A check filter of Aidoku goes to the source only when you change it, as
  the notes of the Aidoku format tell a host to do.

## 2.0.0 (2026-10-23)

A release of fixes, speed, and small comforts, after a full review of the app.

Safety of your data:

- A library file that does not load stays as it is. Asabunko keeps a copy,
  saves nothing over it, and lets you restore a backup or start a new
  library in Settings.
- A book with downloaded chapters stays in the library when you take it off
  the read list. A delete stops the download of that book.
- A downloaded chapter holds only real images. A page of HTML, such as a
  check page, does not count as a page.
- A restore tells you which sources did not install.
- A backup has the local time in its name, so a new backup does not replace
  an older one. The message after a restore shows again.

Fixes:

- The page turns of the reader keep working after quick taps, such as near
  the end of a long comic.
- A novel with no chapters opens with no crash.
- A chapter that cannot open tells you why, such as when its source is not
  installed.
- Two quick taps add a series one time.
- A failed download shows a mark, and the Downloads menu tries it again.
- The faults of the app show on each tab.
- Discover loads again when more sources install.
- A late answer does not go into a newer search or a newer chapter.
- The books of a source list line that you add again find their source.
- Sources that use a web view, such as Comix and Toonkotsu, load with no
  crash.
- LNReader plugins that use gRPC, such as Wuxia World, load their chapters.

Speed:

- A page turn saves the library a short time later, off the main thread.
- The chapters of each book stay in memory until their file changes.
- Two screens that ask for one source get one load, and at most 24 sources
  stay in memory.
- Long webtoon strips are sharp, the page cache has a memory limit, and a
  page downloads one time.
- The check for new chapters asks four books at the same time.

Comforts:

- Keep the screen on while a book is open. Settings, Reader turns it off.
- Sort the read list by date added, last read, title, or unread first. Each
  online book shows its source.
- Pull down in the library to check for new chapters.
- Mark the chapters up to one chapter as read.
- Move a book of the library to another source of its title. Your place
  goes to the chapter with the same number.
- Search the chapter list of a reader by title or number.
- Turn the pages with the keyboard of an iPad.
- Try a source again from its page, or pull down to load it again.

## 1.5.0 (2026-10-23)

- Aidoku sources that draw their pages work: the canvas module draws with
  CoreGraphics, and a source can put the parts of a page in order again or
  decrypt it. MANGA Plus reads now.
- The js module of Aidoku runs scripts in JavaScriptCore, and in a web view
  for the sources that need a page of the site.
- A site behind the browser check of Cloudflare shows a banner. Open the
  page, pass the check one time, and the source loads again by itself.
- The tests read RAR 4 and RAR 5 archives, and import and read a comic of
  600 pages in 4 seconds on the simulator.
- An OPDS catalog gives its Kindle files, such as the MOBI files of Project
  Gutenberg.
- LNReader plugins that take the constants of the LNReader app load, such as
  Novel Fire.

## 1.4.0 (2026-10-23)

- The filters of a source: open a source in Settings, Sources, and tap the
  filter button. Aidoku sources, LNReader plugins, and Paperback extensions
  give their filters: text, choices, many choices with include and exclude,
  and the order of the list.
- The settings of a source: tap the gear on the page of a source. Aidoku
  sources and LNReader plugins keep the values on the device.

## 1.3.0 (2026-10-23)

- Import MOBI, AZW, and AZW3 books with no DRM from Files. A KF8 book, such
  as an AZW3, keeps its styles and its images. A joint MOBI file opens its
  KF8 part.
- Each part of the book is a chapter, with its title from its heading.
- A book with DRM, or with the compression of the Kindle store, gives a
  clear message.

## 1.2.0 (2026-10-23)

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
