import Foundation

/// The postcard format of Rust, which the Aidoku sources use for their data.
/// An unsigned integer is a LEB128 varint, and a signed integer is a zigzag varint.
/// A float is little endian. A string, bytes, and a list start with a varint of their length.
/// An option starts with 0 or 1. An enum starts with the varint of its variant.
public struct PostcardWriter {
    public private(set) var data = Data()

    public init() {}

    public mutating func varint(_ value: UInt64) {
        var value = value
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            data.append(byte)
        } while value != 0
    }

    public mutating func u8(_ value: UInt8) { data.append(value) }
    public mutating func bool(_ value: Bool) { data.append(value ? 1 : 0) }
    public mutating func unsigned(_ value: Int) { varint(UInt64(max(value, 0))) }
    public mutating func signed(_ value: Int64) { varint(UInt64(bitPattern: (value << 1) ^ (value >> 63))) }
    public mutating func signed(_ value: Int) { signed(Int64(value)) }
    public mutating func f32(_ value: Float) { withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
    public mutating func f64(_ value: Double) { withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) } }

    public mutating func bytes(_ value: Data) {
        varint(UInt64(value.count))
        data.append(value)
    }

    public mutating func string(_ value: String) { bytes(Data(value.utf8)) }

    public mutating func option<T>(_ value: T?, _ write: (inout PostcardWriter, T) -> Void) {
        guard let value else { return u8(0) }
        u8(1)
        write(&self, value)
    }

    public mutating func list<T>(_ values: [T], _ write: (inout PostcardWriter, T) -> Void) {
        varint(UInt64(values.count))
        for value in values { write(&self, value) }
    }
}

public enum PostcardError: Error, Equatable {
    case end
    case badString
    case badTag(UInt64)
}

public struct PostcardReader {
    private let data: Data
    private var index: Data.Index

    public init(_ data: Data) {
        self.data = data
        self.index = data.startIndex
    }

    public var isAtEnd: Bool { index >= data.endIndex }

    public mutating func u8() throws -> UInt8 {
        guard index < data.endIndex else { throw PostcardError.end }
        defer { index += 1 }
        return data[index]
    }

    public mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            let byte = try u8()
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { throw PostcardError.badTag(result) }
        }
    }

    public mutating func bool() throws -> Bool { try u8() != 0 }
    public mutating func unsigned() throws -> Int { Int(clamping: try varint()) }

    public mutating func signed() throws -> Int64 {
        let raw = try varint()
        return Int64(bitPattern: (raw >> 1) ^ (0 &- (raw & 1)))
    }

    public mutating func f32() throws -> Float {
        var bits: UInt32 = 0
        for shift in stride(from: 0, to: 32, by: 8) { bits |= UInt32(try u8()) << shift }
        return Float(bitPattern: bits)
    }

    public mutating func f64() throws -> Double {
        var bits: UInt64 = 0
        for shift in stride(from: 0, to: 64, by: 8) { bits |= UInt64(try u8()) << shift }
        return Double(bitPattern: bits)
    }

    public mutating func bytes() throws -> Data {
        let count = try unsigned()
        guard data.endIndex - index >= count else { throw PostcardError.end }
        defer { index += count }
        return data[index..<(index + count)]
    }

    public mutating func string() throws -> String {
        guard let text = String(data: try bytes(), encoding: .utf8) else { throw PostcardError.badString }
        return text
    }

    public mutating func option<T>(_ read: (inout PostcardReader) throws -> T) throws -> T? {
        switch try u8() {
        case 0: return nil
        case 1: return try read(&self)
        case let tag: throw PostcardError.badTag(UInt64(tag))
        }
    }

    public mutating func list<T>(_ read: (inout PostcardReader) throws -> T) throws -> [T] {
        let count = try unsigned()
        var values: [T] = []
        values.reserveCapacity(min(count, 4096))
        for _ in 0..<count { values.append(try read(&self)) }
        return values
    }
}
