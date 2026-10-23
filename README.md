<div align="center">

<img src="assets/brand/logo-full.png" alt="Asabunko" width="320">

### A calm reader for manga, comics, and light novels

_Your files and the sources of the community, in one warm app_

<p align="center">
  <img src="https://img.shields.io/badge/iOS-18%2B-17130F?style=for-the-badge&logo=apple&logoColor=white" alt="iOS 18 or newer"/>
  <img src="https://img.shields.io/badge/Swift-SwiftUI-17130F?style=for-the-badge&logo=swift&logoColor=white" alt="Swift and SwiftUI"/>
</p>

<p align="center">
  <a href="https://github.com/Stiven-Gjekaj/Asabunko/releases/latest"><img src="https://img.shields.io/github/v/release/Stiven-Gjekaj/Asabunko?style=for-the-badge&color=E34659&labelColor=17130F&label=Download" alt="Download the newest release"/></a>
  <a href="https://ko-fi.com/stivengjekaj"><img src="https://img.shields.io/badge/Ko--fi-Support_this_project-17130F?style=for-the-badge&logo=ko-fi&logoColor=white" alt="Support this project on Ko-fi"/></a>
</p>

<p align="center">
  <a href="https://github.com/Stiven-Gjekaj/Asabunko/actions/workflows/ci.yml"><img src="https://github.com/Stiven-Gjekaj/Asabunko/actions/workflows/ci.yml/badge.svg" alt="CI"/></a>
  <img src="https://img.shields.io/badge/license-MIT-17130F?style=flat-square" alt="MIT License"/>
</p>

</div>

---

## Overview

**Asabunko** is an iPhone and iPad app that reads manga, comics, light
novels, and web novels. "Asa" is the morning and "bunko" is a small
paperback library in Japanese. The app has a warm dark look and a paper
look.

It reads the files on your device, and the sources of the community:
OPDS catalogs, LNReader plugins, Suwayomi servers, Aidoku sources, and
Paperback extensions. You paste the URLs of your sources, one on each line,
as in ZettaStream.

Asabunko has no sources in it. Your books stay on your device.

## Features

- Comics: CBZ, CBR, CB7, and CBT files, ZIP, RAR, 7z, and TAR archives, and
  folders of images. The title, the writer, and the direction come from
  ComicInfo.xml
- Novels: EPUB, MOBI, AZW3, TXT, FB2, and HTML files. The chapters and their titles come
  from the book, or from the headings of a TXT file
- PDF, page by page or in one column
- A reader of pages from the right to the left, from the left to the right,
  or in one vertical column, with zoom
- A reader of novels with your font, size, spacing, and margins, and a list
  of the chapters
- A library of two parts: Continue reading, with the page and the progress,
  and the read list of the titles that you bookmark
- Discover: a banner and rows of the popular and the latest titles of your
  sources
- Search: one search in all your sources at the same time. A title that many
  sources have shows one time
- The page of a title compares its sources and shows the source with the
  most chapters. You can choose another source
- Chapters by volume, or in ranges of 50 for a long series
- The filters and the settings of each source
- Aidoku sources that draw or decrypt their pages, such as MANGA Plus
- The browser check of a site, such as Cloudflare, in a web view
- Sources: paste one URL on each line. The app finds the kind of each source
  and installs the sources of each list
- OPDS catalogs, such as Komga, Kavita, and Calibre-web: browse, search,
  read a comic page by page from the server, or download a book
- Web novels with LNReader plugins, which download each chapter as you read
- Suwayomi servers, which run the extensions of Mihon
- Aidoku sources, which run as WebAssembly on the device
- Paperback 0.9 extensions, with their interceptors and their state
- Check all online books for new chapters
- Back up and restore the library in one file
- Keep the screen on, sort the read list, mark chapters as read, and move a
  book to another source
- Warm dark, paper, or the look of the device
- The app tells you when a newer version is available

See [TODO.md](TODO.md) for the next functions.

## Add sources

1. Open Settings, Sources, and tap Add sources.
2. Paste the URLs, one on each line, and tap Save. Some examples:

```
https://komga.example.com/opds/v1.2/catalog
https://raw.githubusercontent.com/LNReader/lnreader-plugins/plugins/v3.0.0/.dist/plugins.min.json
https://aidoku-community.github.io/sources/index.min.json
https://inkdex.github.io/extensions/0.9/stable
http://192.168.1.20:4567
```

3. For a server with an account, write `https://user:password@host/...`. The
   password goes to the Keychain. The list shows only the user name.
4. Asabunko installs the sources of each list in the languages of the
   device. Adult sources stay out until you turn them on. Swipe a source to
   remove it, or open a list to add a source in another language.

You choose your sources, and you are responsible for them and for what you
read.

## Install

Asabunko is not in the App Store.

**With SideStore or AltStore:** add this source one time. The app then gets
each update from it.

```
https://stiven-gjekaj.github.io/sidestore-source/apps.json
```

**By hand:** each release has an unsigned `Asabunko.ipa`. Sign and install it
with one of these tools:

- [AltStore](https://altstore.io) or [SideStore](https://sidestore.io)
- [Sideloadly](https://sideloadly.io)
- [TrollStore](https://github.com/opa334/TrollStore), on a version of iOS
  that it supports

The newest IPA is always at this URL:

```
https://github.com/Stiven-Gjekaj/Asabunko/releases/latest/download/Asabunko.ipa
```

## Project structure

```
App/Sources/
  Model/        the app model, which keeps the library and imports the files
  Screens/      the library, the reader, and the settings
  Components/   the covers, the page loader, and the two readers
  Theme/        the warm colours and the font, from ZettaStream
AsaCore/        the parts that do not need a screen, with their tests
  Sources/CArchive/   the declarations of the libarchive of the system
  Sources/AsaCore/    the archives, the import, ComicInfo.xml, the library,
                      OPDS, and the hosts of the online sources
js/             the JavaScript libraries of the sources, which scripts/build-js.sh bundles
UITests/        the checks in the simulator
assets/brand/   the icon
docs/           the reason behind each choice
scripts/        the build of the IPA
project.yml     the XcodeGen project
```

## Building

You need Xcode 16 or newer and XcodeGen.

```
brew install xcodegen
git clone https://github.com/Stiven-Gjekaj/Asabunko
cd Asabunko
./scripts/build-ipa.sh
```

The IPA is in `build/`. To work in Xcode, run `xcodegen` and open
`Asabunko.xcodeproj`.

A tag such as `v0.1.0` makes the workflow build the IPA and attach it to a
release.

## Testing

```
swift test --package-path AsaCore
xcodebuild -project Asabunko.xcodeproj -scheme Asabunko -destination 'platform=iOS Simulator,name=iPhone 17' test
```

The UI tests of the sources need the small test server of the scripts. It
serves an OPDS catalog and a list of LNReader plugins. Start it, and give its
URL to the tests:

```
python3 scripts/test-server.py 8765 &
TEST_RUNNER_SERVER_URL=http://127.0.0.1:8765 TEST_RUNNER_OPDS_URL=http://127.0.0.1:8765/opds/catalog xcodebuild -project Asabunko.xcodeproj -scheme Asabunko -destination 'platform=iOS Simulator,name=iPhone 17' test
```

With no URL, these tests are skipped. One unit test reads a real LNReader
plugin from the web. It runs with `ASABUNKO_LIVE=1 swift test --package-path AsaCore`.

The unit tests make their own ZIP, 7z, and TAR archives with libarchive. They
cover the reader of the archives, the natural order of the pages,
ComicInfo.xml, the import, the cover, and the library file. The UI tests make
a CBZ, import it into an empty library, read it from the right to the left,
and change the look.

## Documentation

- [docs/decisions.md](docs/decisions.md): each choice and its reason
- [CHANGELOG.md](CHANGELOG.md): what changed, and when
- [TODO.md](TODO.md): the next releases
- [AGENTS.md](AGENTS.md): the rules for an agent that works here

## License

MIT. See [LICENSE](LICENSE). Karla is under the SIL Open Font License, in
[licenses/](licenses/Karla-OFL.txt). The app links the libarchive of the
system, under the BSD License. The Aidoku sources run in WasmKit, under the
Apache License 2.0, with SwiftSoup, under the MIT License. The JavaScript bundle has cheerio,
htmlparser2, dayjs, @noble/ciphers, and core-js, under the MIT License. Their
license texts are at the end of `AsaCore/Sources/AsaCore/Resources/libraries.js`.
