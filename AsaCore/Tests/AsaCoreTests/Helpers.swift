import CArchive
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A new empty folder for one test.
func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("AsaCoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

enum ArchiveKind { case zip, sevenZip, tar }

/// Writes an archive with the files in the given order, with the libarchive of the system.
func writeArchive(_ kind: ArchiveKind, to url: URL, files: [(String, Data)]) throws {
    let archive = archive_write_new()!
    defer { archive_write_free(archive) }
    switch kind {
    case .zip: archive_write_set_format_zip(archive)
    case .sevenZip: archive_write_set_format_7zip(archive)
    case .tar: archive_write_set_format_pax_restricted(archive)
    }
    guard archive_write_open_filename(archive, url.path) == ARCHIVE_OK else {
        throw NSError(domain: "writeArchive", code: 1)
    }
    for (path, data) in files {
        let entry = archive_entry_new()!
        archive_entry_set_pathname(entry, path)
        archive_entry_set_filetype(entry, UInt32(AE_IFREG))
        archive_entry_set_perm(entry, 0o644)
        archive_entry_set_size(entry, Int64(data.count))
        archive_write_header(archive, entry)
        _ = data.withUnsafeBytes { archive_write_data(archive, $0.baseAddress, data.count) }
        archive_entry_free(entry)
    }
    archive_write_close(archive)
}

/// A real PNG of one colour, so that ImageIO can read it.
func pngData(width: Int = 40, height: Int = 60, gray: CGFloat = 0.5) -> Data {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

func comicInfo(_ fields: [String: String]) -> Data {
    let body = fields.sorted { $0.key < $1.key }.map { "  <\($0.key)>\($0.value)</\($0.key)>" }.joined(separator: "\n")
    return Data("<?xml version=\"1.0\"?>\n<ComicInfo>\n\(body)\n</ComicInfo>\n".utf8)
}
