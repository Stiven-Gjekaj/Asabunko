import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AsaCore

@Suite struct ChapterDownloadTests {
    private let chapter = Novel.Chapter(title: "One", path: "chapters/00001.html", remote: "c1")

    @Test func downloadsThePagesInOrderWithTheExtensionOfTheirKind() async throws {
        let book = try temporaryFolder()
        let requests = [URL(string: "https://x.test/p/1")!, URL(string: "https://x.test/p/2.webp?w=800")!].map { URLRequest(url: $0) }
        let fetcher: Fetcher = { request in
            let png = request.url!.path == "/p/1"
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: png ? ["Content-Type": "image/png"] : [:])!
            return (tinyPNG(request.url!.path == "/p/1" ? 1 : 2), response)
        }
        let steps = Counter()
        try await ChapterDownload.download(requests, chapter: chapter, in: book, fetcher: fetcher) { done, _ in steps.add(done) }
        let pages = ChapterDownload.pages(of: chapter, in: book)
        #expect(pages.map(\.lastPathComponent) == ["0001.png", "0002.webp"])
        #expect(try Data(contentsOf: pages[1]) == tinyPNG(2))
        #expect(steps.values == [1, 2])
        #expect(ChapterDownload.isDownloaded(chapter, in: book))
        ChapterDownload.remove(chapter, in: book)
        #expect(!ChapterDownload.isDownloaded(chapter, in: book))
    }

    @Test func copiesAPageThatTheSourceDrewOnTheDevice() async throws {
        let book = try temporaryFolder()
        let drawn = try temporaryFolder().appendingPathComponent("page.png")
        try tinyPNG(3).write(to: drawn)
        let fetcher: Fetcher = { _ in throw URLError(.notConnectedToInternet) }
        try await ChapterDownload.download([URLRequest(url: drawn)], chapter: chapter, in: book, fetcher: fetcher) { _, _ in }
        let pages = ChapterDownload.pages(of: chapter, in: book)
        #expect(pages.map(\.lastPathComponent) == ["0001.png"])
        #expect(try Data(contentsOf: pages[0]) == tinyPNG(3))
    }

    @Test func keepsNoHalfChapterWhenAPageFails() async throws {
        let book = try temporaryFolder()
        let requests = (1...3).map { URLRequest(url: URL(string: "https://x.test/p/\($0)")!) }
        let fetcher: Fetcher = { request in
            let code = request.url!.path == "/p/3" ? 404 : 200
            return (tinyPNG(1), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
        }
        await #expect(throws: URLError.self) { try await ChapterDownload.download(requests, chapter: chapter, in: book, fetcher: fetcher) }
        #expect(ChapterDownload.pages(of: chapter, in: book).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: book.appendingPathComponent("chapters/00001.part").path))
    }

    @Test func refusesAPageOfHTMLThatCameWithTheCode200() async throws {
        let book = try temporaryFolder()
        let fetcher: Fetcher = { request in
            (Data("<html><title>Just a moment...</title></html>".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/jpeg"])!)
        }
        await #expect(throws: URLError.self) {
            try await ChapterDownload.download([URLRequest(url: URL(string: "https://x.test/p/1")!)], chapter: chapter, in: book, fetcher: fetcher)
        }
        #expect(!ChapterDownload.isDownloaded(chapter, in: book), "A chapter with a page that is not an image is not downloaded.")
    }

    @Test func namesAPageFromItsKindOrItsURL() {
        let url = URL(string: "https://x.test/a/page.GIF")!
        #expect(ChapterDownload.pageName(0, mimeType: "image/jpeg; charset=binary", url: url) == "0001.jpg")
        #expect(ChapterDownload.pageName(9, mimeType: nil, url: url) == "0010.gif")
        #expect(ChapterDownload.pageName(1, mimeType: "application/octet-stream", url: URL(string: "https://x.test/p")!) == "0002.jpg")
    }
}

/// A PNG of one pixel. The number changes its colour, so two numbers give two files.
func tinyPNG(_ number: Int) -> Data {
    var pixel: [UInt8] = [UInt8(number * 40 % 256), 0, 0, 255]
    let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [Int] = []
    func add(_ value: Int) { lock.withLock { list.append(value) } }
    var values: [Int] { lock.withLock { list } }

    @Test func measuresTheFilesOfAFolder() throws {
        let folder = try temporaryFolder()
        #expect(FolderSize.bytes(of: folder.appendingPathComponent("none")) == 0)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("chapters/0001"), withIntermediateDirectories: true)
        try Data(count: 10_000).write(to: folder.appendingPathComponent("chapters/0001/1.png"))
        try Data(count: 5_000).write(to: folder.appendingPathComponent("book.json"))
        let size = FolderSize.bytes(of: folder)
        // The file system gives each file whole blocks, so the space is at least the bytes of the files.
        #expect(size >= 15_000)
        #expect(size < 15_000 + 64 * 1024)
        #expect(FolderSize.bytes(of: folder.appendingPathComponent("chapters")) >= 10_000)
    }
}
