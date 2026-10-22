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
