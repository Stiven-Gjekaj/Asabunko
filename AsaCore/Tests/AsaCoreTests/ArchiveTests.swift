import Foundation
import Testing
@testable import AsaCore

@Suite struct ArchiveTests {
    @Test(arguments: [ArchiveKind.zip, .sevenZip, .tar])
    func readsEachFileWithItsData(kind: ArchiveKind) throws {
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent("book")
        try writeArchive(kind, to: url, files: [("b.txt", Data("second".utf8)), ("a/c.txt", Data("first".utf8))])

        var files: [String: String] = [:]
        try ArchiveReader.forEachFile(in: url) { entry, read in
            files[entry.path] = String(decoding: try read(), as: UTF8.self)
        }
        #expect(files == ["b.txt": "second", "a/c.txt": "first"])
    }

    @Test func skipsAFileThatTheCallerDoesNotRead() throws {
        let url = try temporaryFolder().appendingPathComponent("book.zip")
        try writeArchive(.zip, to: url, files: [("one", Data("1".utf8)), ("two", Data("2".utf8))])

        var read: [String] = []
        try ArchiveReader.forEachFile(in: url) { entry, data in
            if entry.path == "two" { read.append(String(decoding: try data(), as: UTF8.self)) }
        }
        #expect(read == ["2"])
    }

    @Test func failsOnAFileThatIsNotAnArchive() throws {
        let url = try temporaryFolder().appendingPathComponent("book.cbz")
        try Data("this is plain text and no archive".utf8).write(to: url)
        #expect(throws: ArchiveError.self) {
            try ArchiveReader.forEachFile(in: url) { _, _ in }
        }
    }
}
