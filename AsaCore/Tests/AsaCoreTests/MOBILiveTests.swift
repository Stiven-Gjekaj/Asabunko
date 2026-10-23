import Foundation
import Testing
@testable import AsaCore

/// Imports real Kindle books of Project Gutenberg from the web. It runs only with ASABUNKO_LIVE=1.
@Suite struct MOBILiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ASABUNKO_LIVE"] == "1"), arguments: [
        ("https://www.gutenberg.org/ebooks/11.kf8.images", "azw3"),
        ("https://www.gutenberg.org/ebooks/11.kindle.images", "mobi"),
    ])
    func importsAGutenbergBook(address: String, ext: String) async throws {
        let (data, _) = try await URLSession.shared.data(from: URL(string: address)!)
        let folder = try temporaryFolder()
        let file = folder.appendingPathComponent("alice.\(ext)")
        try data.write(to: file)
        let book = folder.appendingPathComponent("book")
        let novel = try MOBIImporter.importBook(from: file, into: book)
        #expect(novel.title.contains("Alice"))
        #expect(novel.author?.contains("Carroll") == true)
        #expect(novel.chapters.count >= 5)
        let all = try novel.chapters.map { String(decoding: try Data(contentsOf: book.appendingPathComponent($0.path)), as: UTF8.self) }.joined()
        #expect(all.contains("rabbit-hole"), "The text of the first chapter is in a part.")
        #expect(all.contains("Alice’s Evidence") || all.contains("Alice's Evidence"), "The last chapter is in a part.")
        #expect(!all.contains("kindle:embed"), "Each image link points to a file.")
        #expect(FileManager.default.fileExists(atPath: book.appendingPathComponent("cover.jpg").path))
        print("LIVE \(ext): \(novel.chapters.count) chapters:", novel.chapters.prefix(6).map { $0.title ?? "-" })
    }
}
