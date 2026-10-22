import Foundation
import ImageIO
import Testing
@testable import AsaCore

@Suite struct ComicImporterTests {
    @Test func copiesThePagesInTheNaturalOrderAndSkipsTheFilesOfMacOSAndThePathsOut() throws {
        let work = try temporaryFolder()
        let archive = work.appendingPathComponent("My_Comic_v01.cbz")
        try writeArchive(.zip, to: archive, files: [
            ("p10.png", pngData(gray: 0.10)),
            ("__MACOSX/._p1.png", Data("resource fork".utf8)),
            ("p2.png", pngData(gray: 0.02)),
            ("notes.txt", Data("no page".utf8)),
            ("p1.png", pngData(gray: 0.01)),
            ("../../escape.png", pngData(gray: 0.99)),
        ])
        let book = work.appendingPathComponent("book", isDirectory: true)

        let result = try ComicImporter.importComic(from: archive, into: book)

        #expect(result.title == "My Comic v01")
        #expect(result.pageCount == 3)
        let pages = ComicImporter.pages(in: book)
        #expect(pages.map(\.lastPathComponent) == ["0001.png", "0002.png", "0003.png"])
        #expect(try Data(contentsOf: pages[0]) == pngData(gray: 0.01))
        #expect(try Data(contentsOf: pages[1]) == pngData(gray: 0.02))
        #expect(try Data(contentsOf: pages[2]) == pngData(gray: 0.10))
        #expect(!FileManager.default.fileExists(atPath: work.appendingPathComponent("escape.png").path))
        #expect(!FileManager.default.fileExists(atPath: book.appendingPathComponent(".staging").path))
    }

    @Test(arguments: [("cb7", ArchiveKind.sevenZip), ("cbt", .tar)])
    func readsTheOtherArchives(ext: String, kind: ArchiveKind) throws {
        let work = try temporaryFolder()
        let archive = work.appendingPathComponent("Book.\(ext)")
        try writeArchive(kind, to: archive, files: [("b.png", pngData()), ("a.png", pngData())])
        let result = try ComicImporter.importComic(from: archive, into: work.appendingPathComponent("book"))
        #expect(result.pageCount == 2)
    }

    @Test func takesTheTitleAndTheDirectionFromComicInfo() throws {
        let work = try temporaryFolder()
        let archive = work.appendingPathComponent("file.cbz")
        try writeArchive(.zip, to: archive, files: [
            ("Sub/ComicInfo.xml", comicInfo(["Series": "Berserk", "Number": "1", "Manga": "YesAndRightToLeft"])),
            ("001.png", pngData()),
        ])
        let result = try ComicImporter.importComic(from: archive, into: work.appendingPathComponent("book"))
        #expect(result.title == "Berserk 1")
        #expect(result.info?.readingMode == .rightToLeft)
    }

    @Test func importsAFolderOfImagesWithChapters() throws {
        let work = try temporaryFolder()
        let source = work.appendingPathComponent("Webtoon", isDirectory: true)
        for (path, gray) in [("Ch 10/1.png", 0.3), ("Ch 2/1.png", 0.2), ("Ch 2/.hidden.png", 0.9)] {
            let file = source.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try pngData(gray: gray).write(to: file)
        }
        let book = work.appendingPathComponent("book", isDirectory: true)

        let result = try ComicImporter.importComic(from: source, into: book)

        #expect(result.title == "Webtoon")
        #expect(result.pageCount == 2)
        #expect(try Data(contentsOf: ComicImporter.pages(in: book)[0]) == pngData(gray: 0.2))
    }

    @Test func failsAndLeavesNoFolderWhenTheArchiveHasNoImages() throws {
        let work = try temporaryFolder()
        let archive = work.appendingPathComponent("empty.cbz")
        try writeArchive(.zip, to: archive, files: [("readme.txt", Data("text".utf8))])
        let book = work.appendingPathComponent("book")
        #expect(throws: ImportError.noPages) {
            try ComicImporter.importComic(from: archive, into: book)
        }
        #expect(!FileManager.default.fileExists(atPath: book.path))
    }

    @Test func refusesAKindOfFileThatItCannotRead() throws {
        let file = try temporaryFolder().appendingPathComponent("song.mp3")
        try Data().write(to: file)
        #expect(throws: ImportError.unsupported("mp3")) {
            try ComicImporter.importComic(from: file, into: file.deletingLastPathComponent().appendingPathComponent("book"))
        }
    }

    @Test func makesASmallCover() throws {
        let work = try temporaryFolder()
        let page = work.appendingPathComponent("page.png")
        try pngData(width: 1200, height: 1800).write(to: page)
        let cover = work.appendingPathComponent("cover.jpg")
        try Thumbnail.make(from: page, to: cover, maxPixels: 300)
        let source = try #require(CGImageSourceCreateWithURL(cover as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 300)
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 200)
    }
}

@Suite struct ArchiveNameTests {
    @Test func theTestArchiveHoldsThePathOut() throws {
        let archive = try temporaryFolder().appendingPathComponent("a.zip")
        try writeArchive(.zip, to: archive, files: [("../../escape.png", pngData())])
        var paths: [String] = []
        try ArchiveReader.forEachFile(in: archive) { entry, _ in paths.append(entry.path) }
        #expect(paths == ["../../escape.png"])
        #expect(!ComicImporter.isPage("../../escape.png"))
    }
}
