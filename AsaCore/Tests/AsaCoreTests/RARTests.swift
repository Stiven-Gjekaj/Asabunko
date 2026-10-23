import CryptoKit
import Foundation
import Testing
@testable import AsaCore

/// The RAR files of the tests of libarchive, under the BSD License. No tool on a Mac writes a RAR,
/// so the test keeps these small files as text. A CBR is a RAR, and it opens on the same path as a CBZ.
@Suite struct RARTests {
    /// test_read_format_rar.rar: RAR 4 with test.txt, a link, and testdir/test.txt.
    private let rar4 = "UmFyIRoHAM+QcwAADQAAAAAAAACEUnQgkDIAFAAAABQAAAADQqLIvrd22j4UMAgApIEAAHRlc3QudHh0gAi3dto+t3baPnRlc3QgdGV4dCBkb2N1bWVudA0KnS90IJAyAAgAAAAIAAAAA3tEybbRTNg+FDAIAP+hAAB0ZXN0bGlua8AI0UzYPlBf2j50ZXN0LnR4dM3gdCCQOgAUAAAAFAAAAANCosi+Y3faPhQwEACkgQAAdGVzdGRpclx0ZXN0LnR4dMDMY3faPmN32j50ZXN0IHRleHQgZG9jdW1lbnQNCqHIdOCQMQAAAAAAAAAAAAMAAAAAY3faPhQwBwDtQQAAdGVzdGRpcsDMY3faPmR32j7m53TgkDYAAAAAAAAAAAADAAAAAJ2r1T4UMAwA7UEAAHRlc3RlbXB0eWRpcoDMnavVPsVd2j7EPXsAQAcA"
    /// test_read_format_rar5_compressed.rar: RAR 5 with one compressed file of 1200 bytes.
    private let rar5Compressed = "UmFyIRoHAQDz4YLrCwEFBwAGAQGAgIAAicZf2iYCAwvpAgSwCaSDAs1wynyABQEIdGVzdC5iaW4KAxOLV6xb+BitHsr0ZQEnZWBUH1V2Xb+UknHJz2WWWQxw2WWTGMWSE4ZCSSThkJCSSSQk45JJIQhJJCEJJJCSSEISEs21b3t9Mw6AfR0Drj+eup/3Qf732vfdea86X+gAQAEAyCCfn49vX08vHv7uzr6uno5+Xk4+Lh4N/d3NrZ19bV1NPS0M/NzMrJyMfGxcTDwb+9vLu5uLe2tbSzsrGvrq2rqqmnpaSjoqGgn52cm5mXlpSTSyUjIR6FAfjoyKiYc6cNmoaEgoB+fHt6eHZ0c3Jxb21raWdlY2FfXVtZV1VTITf1/I/QJT6JTn+ESXRYowZ5YXajgppimUF+ZC0XadRjLDOMCoR/+glMZpCl9lUKxWVguLAZFoNy4HdeEGwA8xBIyCeZhWNAumoZbYN5uHg4Bgcg+uYROgpnYYDwNt6Hu9h1fQjfxYQI0YMecKHk0Jg2L44OY6HCIEqeGFFjtjQ/nxUIBsIQ0IhNIxnJAvJQAdd1ZRAwUEAA=="
    /// test_read_format_rar5_stored.rar: RAR 5 with one stored file.
    private let rar5Stored = "UmFyIRoHAQAzkrXlCgEFBgAFAQGAgAA4MAZjLAIDC50ABJ0ApIMCtEOglYAAAQ5oZWxsb3dvcmxkLnR4dAoDE34Oq1tW6Q4aaGVsbG8gbGliYXJjaGl2ZSB0ZXN0IHN1aXRlIQodd1ZRAwUEAA=="

    private func files(_ base64: String) throws -> [String: Data] {
        let file = try temporaryFolder().appendingPathComponent("a.cbr")
        try Data(base64Encoded: base64)!.write(to: file)
        var files: [String: Data] = [:]
        try ArchiveReader.forEachFile(in: file) { entry, read in files[entry.path] = try read() }
        return files
    }

    @Test func readsARAR4Archive() throws {
        let files = try files(rar4)
        #expect(files["test.txt"] == Data("test text document\r\n".utf8))
        #expect(files["testdir/test.txt"] == Data("test text document\r\n".utf8))
    }

    @Test func readsACompressedRAR5Archive() throws {
        let files = try files(rar5Compressed)
        let data = try #require(files["test.bin"])
        #expect(data.count == 1200)
        #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == "588870a2dade35c2650fbb7898c9a9c7f21fce7c281198604e8d0c9737f2c375")
    }

    @Test func readsAStoredRAR5Archive() throws {
        #expect(try files(rar5Stored)["helloworld.txt"] == Data("hello libarchive test suite!\n".utf8))
    }

    @Test func aCBRWithNoImagesGivesTheFaultOfAComic() throws {
        let file = try temporaryFolder().appendingPathComponent("Text.cbr")
        try Data(base64Encoded: rar5Stored)!.write(to: file)
        #expect(throws: ImportError.noPages) { try ComicImporter.importComic(from: file, into: try temporaryFolder().appendingPathComponent("b")) }
    }
}
