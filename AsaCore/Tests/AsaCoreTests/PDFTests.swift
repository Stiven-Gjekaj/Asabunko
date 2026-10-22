import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AsaCore

/// Writes a PDF with the pages and the metadata, in the test.
private func writePDF(to url: URL, pages: Int, title: String?, author: String?, password: String? = nil) {
    var info: [CFString: Any] = [:]
    if let title { info[kCGPDFContextTitle] = title }
    if let author { info[kCGPDFContextAuthor] = author }
    if let password { info[kCGPDFContextUserPassword] = password; info[kCGPDFContextOwnerPassword] = password }
    var box = CGRect(x: 0, y: 0, width: 400, height: 600)
    let context = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary)!
    for _ in 0..<pages {
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 50, y: 50, width: 300, height: 500))
        context.endPDFPage()
    }
    context.closePDF()
}

@Suite struct PDFTests {
    @Test func copiesThePDFWithItsTitleItsAuthorAndACover() throws {
        let work = try temporaryFolder()
        let file = work.appendingPathComponent("scan.pdf")
        writePDF(to: file, pages: 3, title: "Night Notes", author: "Mira")
        let folder = work.appendingPathComponent("b")
        let result = try BookImporter.importBook(from: file, into: folder)
        #expect(result == ImportedBook(format: .pdf, title: "Night Notes", author: "Mira", summary: nil, pageCount: 3, mode: .leftToRight))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("book.pdf").path))
        let cover = try #require(CGImageSourceCreateWithURL(folder.appendingPathComponent("cover.jpg") as CFURL, nil))
        let size = try #require(CGImageSourceCopyPropertiesAtIndex(cover, 0, nil) as? [CFString: Any])
        #expect(size[kCGImagePropertyPixelHeight] as? Int == 600)
        #expect(size[kCGImagePropertyPixelWidth] as? Int == 400)
    }

    @Test func takesTheTitleFromTheNameOfTheFileWhenThePDFHasNone() throws {
        let work = try temporaryFolder()
        let file = work.appendingPathComponent("Lecture_Notes.pdf")
        writePDF(to: file, pages: 1, title: nil, author: nil)
        #expect(try BookImporter.importBook(from: file, into: work.appendingPathComponent("b")).title == "Lecture Notes")
    }

    @Test func refusesAPDFWithAPassword() throws {
        let work = try temporaryFolder()
        let file = work.appendingPathComponent("locked.pdf")
        writePDF(to: file, pages: 1, title: "Secret", author: nil, password: "pass")
        let folder = work.appendingPathComponent("b")
        #expect(throws: PDFImporter.Failure.locked) { try BookImporter.importBook(from: file, into: folder) }
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func refusesAFileThatIsNotAPDF() throws {
        let work = try temporaryFolder()
        let file = work.appendingPathComponent("fake.pdf")
        try Data("not a pdf".utf8).write(to: file)
        #expect(throws: PDFImporter.Failure.notPDF) { try BookImporter.importBook(from: file, into: work.appendingPathComponent("b")) }
    }
}
