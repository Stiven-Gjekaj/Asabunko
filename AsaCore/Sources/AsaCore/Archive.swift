import CArchive
import Foundation

/// One regular file in an archive.
public struct ArchiveEntry: Sendable, Equatable {
    /// The path inside the archive, as the archive writes it.
    public let path: String
    /// The size in bytes, or 0 when the archive does not give it.
    public let size: Int64
}

public enum ArchiveError: Error, Equatable {
    case cannotOpen(String)
    case cannotRead(String)
}

/// Reads a ZIP, RAR, RAR5, 7z, or TAR archive with the libarchive of the system.
/// A CBZ is a ZIP, a CBR is a RAR, a CB7 is a 7z, and a CBT is a TAR.
public enum ArchiveReader {
    private static let blockSize = 64 * 1024

    /// Calls `body` for each regular file, in the order of the archive.
    /// The `read` function gives the data of that file. It operates only during the call.
    public static func forEachFile(
        in url: URL,
        _ body: (ArchiveEntry, _ read: () throws -> Data) throws -> Void
    ) throws {
        guard let archive = archive_read_new() else { throw ArchiveError.cannotOpen(url.lastPathComponent) }
        defer { archive_read_free(archive) }
        archive_read_support_filter_all(archive)
        archive_read_support_format_zip(archive)
        archive_read_support_format_rar(archive)
        archive_read_support_format_rar5(archive)
        archive_read_support_format_7zip(archive)
        archive_read_support_format_tar(archive)

        guard archive_read_open_filename(archive, url.path, blockSize) == ARCHIVE_OK else {
            throw ArchiveError.cannotOpen(message(archive) ?? url.lastPathComponent)
        }

        var entry: OpaquePointer?
        while true {
            let status = archive_read_next_header(archive, &entry)
            if status == ARCHIVE_EOF { break }
            guard status == ARCHIVE_OK || status == ARCHIVE_WARN, let entry else {
                throw ArchiveError.cannotRead(message(archive) ?? url.lastPathComponent)
            }
            guard Int32(archive_entry_filetype(entry)) == AE_IFREG, let path = pathname(entry) else {
                archive_read_data_skip(archive)
                continue
            }
            var consumed = false
            let file = ArchiveEntry(path: path, size: max(0, archive_entry_size(entry)))
            try body(file) {
                consumed = true
                return try readData(archive)
            }
            if !consumed { archive_read_data_skip(archive) }
        }
    }

    private static func readData(_ archive: OpaquePointer) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: blockSize)
        while true {
            let count = buffer.withUnsafeMutableBytes { archive_read_data(archive, $0.baseAddress, blockSize) }
            if count == 0 { return data }
            guard count > 0 else { throw ArchiveError.cannotRead(message(archive) ?? "data") }
            data.append(buffer, count: count)
        }
    }

    private static func pathname(_ entry: OpaquePointer) -> String? {
        if let utf8 = archive_entry_pathname_utf8(entry) { return String(cString: utf8) }
        guard let raw = archive_entry_pathname(entry) else { return nil }
        // A name that is not UTF-8, such as Shift JIS from an old archive, keeps its bytes as Latin-1.
        let bytes = Data(bytes: raw, count: strlen(raw))
        return String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .isoLatin1)
    }

    private static func message(_ archive: OpaquePointer) -> String? {
        archive_error_string(archive).map { String(cString: $0) }
    }
}
