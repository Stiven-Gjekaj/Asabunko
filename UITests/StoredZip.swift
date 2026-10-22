import Foundation

/// Writes a ZIP with no compression, so that a UI test can make its own CBZ.
enum StoredZip {
    static func write(_ files: [(String, Data)], to url: URL) throws {
        var archive = Data()
        var directory = Data()
        for (name, data) in files {
            let offset = UInt32(archive.count)
            let crc = crc32(data)
            let nameBytes = Data(name.utf8)
            archive.append(le32(0x0403_4B50))
            archive.append(le16(20)); archive.append(le16(0)); archive.append(le16(0))
            archive.append(le16(0)); archive.append(le16(0x21))
            archive.append(le32(crc)); archive.append(le32(UInt32(data.count))); archive.append(le32(UInt32(data.count)))
            archive.append(le16(UInt16(nameBytes.count))); archive.append(le16(0))
            archive.append(nameBytes); archive.append(data)

            directory.append(le32(0x0201_4B50))
            directory.append(le16(20)); directory.append(le16(20)); directory.append(le16(0)); directory.append(le16(0))
            directory.append(le16(0)); directory.append(le16(0x21))
            directory.append(le32(crc)); directory.append(le32(UInt32(data.count))); directory.append(le32(UInt32(data.count)))
            directory.append(le16(UInt16(nameBytes.count))); directory.append(le16(0)); directory.append(le16(0))
            directory.append(le16(0)); directory.append(le16(0)); directory.append(le32(0)); directory.append(le32(offset))
            directory.append(nameBytes)
        }
        let start = UInt32(archive.count)
        archive.append(directory)
        archive.append(le32(0x0605_4B50)); archive.append(le16(0)); archive.append(le16(0))
        archive.append(le16(UInt16(files.count))); archive.append(le16(UInt16(files.count)))
        archive.append(le32(UInt32(directory.count))); archive.append(le32(start)); archive.append(le16(0))
        try archive.write(to: url)
    }

    private static func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private static func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1))) }
        }
        return ~crc
    }
}
