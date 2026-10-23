import Foundation
import WasmKit

/// The function imports of a WebAssembly module with their types, from its type and import sections.
/// The host gives a stub of the same type to each import that it does not have, so that a source
/// with an extra import still loads.
enum WasmImports {
    struct Function: Hashable {
        let module: String
        let name: String
        let parameters: [ValueType]
        let results: [ValueType]
    }

    static func functions(in bytes: [UInt8]) -> [Function] {
        var index = 8
        var types: [([ValueType], [ValueType])] = []
        var imports: [Function] = []
        func leb() -> Int {
            var result = 0, shift = 0
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                result |= Int(byte & 0x7F) << shift
                if byte & 0x80 == 0 { break }
                shift += 7
            }
            return result
        }
        func name() -> String {
            let count = leb()
            defer { index += count }
            return String(decoding: bytes[index..<min(index + count, bytes.count)], as: UTF8.self)
        }
        func valueType(_ byte: UInt8) -> ValueType {
            switch byte {
            case 0x7E: .i64
            case 0x7D: .f32
            case 0x7C: .f64
            default: .i32
            }
        }
        guard bytes.count > 8 else { return [] }
        while index < bytes.count {
            let section = bytes[index]
            index += 1
            let size = leb()
            let end = index + size
            if section == 1 {
                for _ in 0..<leb() {
                    index += 1 // 0x60, a function type
                    let parameters = (0..<leb()).map { _ in defer { index += 1 }; return valueType(bytes[index]) }
                    let results = (0..<leb()).map { _ in defer { index += 1 }; return valueType(bytes[index]) }
                    types.append((parameters, results))
                }
            } else if section == 2 {
                for _ in 0..<leb() {
                    let module = name(), field = name()
                    let kind = bytes[index]
                    index += 1
                    switch kind {
                    case 0:
                        let type = leb()
                        if types.indices.contains(type) { imports.append(Function(module: module, name: field, parameters: types[type].0, results: types[type].1)) }
                    case 1: index += 1; let flags = leb(); _ = leb(); if flags & 1 == 1 { _ = leb() }
                    case 2: let flags = leb(); _ = leb(); if flags & 1 == 1 { _ = leb() }
                    case 3: index += 2
                    default: break
                    }
                }
            }
            index = end
        }
        return imports
    }
}
