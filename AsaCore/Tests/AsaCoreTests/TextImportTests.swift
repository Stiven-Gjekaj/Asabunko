import Foundation
import Testing
@testable import AsaCore

@Suite struct TextTests {
    @Test func splitsAtTheHeadingsOfTheChapters() throws {
        let work = try temporaryFolder()
        let file = work.appendingPathComponent("My_Web_Novel.txt")
        try Data("Chapter 1: Dawn\nThe sun came up.\n\nShe read.\nChapter 2 - Noon\nLunch & tea <now>.\n".utf8).write(to: file)
        let result = try BookImporter.importBook(from: file, into: work.appendingPathComponent("b"))
        #expect(result.title == "My Web Novel")
        #expect(result.pageCount == 2)
        let novel = try Novel.load(from: work.appendingPathComponent("b"))
        #expect(novel.chapters.map(\.title) == ["Chapter 1: Dawn", "Chapter 2 - Noon"])
        let second = try String(contentsOf: work.appendingPathComponent("b/" + novel.chapters[1].path), encoding: .utf8)
        #expect(second.contains("<p>Lunch &amp; tea &lt;now&gt;.</p>"))
        let first = try String(contentsOf: work.appendingPathComponent("b/" + novel.chapters[0].path), encoding: .utf8)
        #expect(first.contains("<p>The sun came up.</p>\n<p>She read.</p>"))
    }

    @Test func findsChineseAndJapaneseHeadings() {
        let parts = TextImporter.split("序\n第一章 出发\n内容\n第二章 到达\n内容\n")
        #expect(parts.map(\.title) == [nil, "第一章 出发", "第二章 到达"])
    }

    @Test func givesPartsToALongTextWithNoHeadings() {
        let paragraph = String(repeating: "word ", count: 2_000)
        let parts = TextImporter.split(Array(repeating: paragraph, count: 20).joined(separator: "\n"))
        #expect(parts.count == 4)
        #expect(parts.first?.title == "Part 1")
    }

    @Test func readsShiftJIS() throws {
        let data = try #require("こんにちは、世界".data(using: .shiftJIS))
        #expect(TextDecoding.decode(data) == "こんにちは、世界")
    }

    @Test func readsGB18030() throws {
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let data = try #require("第一章 少女在早晨读书。".data(using: gb))
        #expect(TextDecoding.decode(data) == "第一章 少女在早晨读书。")
    }

    @Test func readsUTF16WithAByteOrderMark() throws {
        let data = try #require("Hello".data(using: .utf16))
        #expect(TextDecoding.decode(data) == "Hello")
    }

    @Test func keepsAnHTMLFileAsOneChapter() throws {
        let work = try temporaryFolder()
        let file = work.appendingPathComponent("page.html")
        try Data("<html><head><title>A <b>Page</b></title></head><body><p>x</p></body></html>".utf8).write(to: file)
        let result = try BookImporter.importBook(from: file, into: work.appendingPathComponent("b"))
        #expect(result.title == "A Page")
        #expect(try Novel.load(from: work.appendingPathComponent("b")).chapters == [.init(title: nil, path: "chapter.html")])
    }
}

@Suite struct WesternTextTests {
    @Test func readsWindows1252() throws {
        let data = try #require("A café in the morning, with crème brûlée.".data(using: .windowsCP1252))
        #expect(TextDecoding.decode(data) == "A café in the morning, with crème brûlée.")
    }
}
