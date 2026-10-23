import Foundation
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
            return (Data(request.url!.absoluteString.utf8), response)
        }
        let steps = Counter()
        try await ChapterDownload.download(requests, chapter: chapter, in: book, fetcher: fetcher) { done, _ in steps.add(done) }
        let pages = ChapterDownload.pages(of: chapter, in: book)
        #expect(pages.map(\.lastPathComponent) == ["0001.png", "0002.webp"])
        #expect(try Data(contentsOf: pages[1]) == Data("https://x.test/p/2.webp?w=800".utf8))
        #expect(steps.values == [1, 2])
        #expect(ChapterDownload.isDownloaded(chapter, in: book))
        ChapterDownload.remove(chapter, in: book)
        #expect(!ChapterDownload.isDownloaded(chapter, in: book))
    }

    @Test func copiesAPageThatTheSourceDrewOnTheDevice() async throws {
        let book = try temporaryFolder()
        let drawn = try temporaryFolder().appendingPathComponent("page.png")
        try Data("drawn".utf8).write(to: drawn)
        let fetcher: Fetcher = { _ in throw URLError(.notConnectedToInternet) }
        try await ChapterDownload.download([URLRequest(url: drawn)], chapter: chapter, in: book, fetcher: fetcher) { _, _ in }
        let pages = ChapterDownload.pages(of: chapter, in: book)
        #expect(pages.map(\.lastPathComponent) == ["0001.png"])
        #expect(try Data(contentsOf: pages[0]) == Data("drawn".utf8))
    }

    @Test func keepsNoHalfChapterWhenAPageFails() async throws {
        let book = try temporaryFolder()
        let requests = (1...3).map { URLRequest(url: URL(string: "https://x.test/p/\($0)")!) }
        let fetcher: Fetcher = { request in
            let code = request.url!.path == "/p/3" ? 404 : 200
            return (Data("x".utf8), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
        }
        await #expect(throws: URLError.self) { try await ChapterDownload.download(requests, chapter: chapter, in: book, fetcher: fetcher) }
        #expect(ChapterDownload.pages(of: chapter, in: book).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: book.appendingPathComponent("chapters/00001.part").path))
    }

    @Test func namesAPageFromItsKindOrItsURL() {
        let url = URL(string: "https://x.test/a/page.GIF")!
        #expect(ChapterDownload.pageName(0, mimeType: "image/jpeg; charset=binary", url: url) == "0001.jpg")
        #expect(ChapterDownload.pageName(9, mimeType: nil, url: url) == "0010.gif")
        #expect(ChapterDownload.pageName(1, mimeType: "application/octet-stream", url: URL(string: "https://x.test/p")!) == "0002.jpg")
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [Int] = []
    func add(_ value: Int) { lock.withLock { list.append(value) } }
    var values: [Int] { lock.withLock { list } }
}
