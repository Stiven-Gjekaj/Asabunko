import Foundation
import Testing
import WAT
import WasmKit

@Suite struct WasmKitTests {
    /// Checks the parts of WasmKit that the host of Aidoku uses: a host import, the memory, and an export.
    @Test func callsAHostImportAndReadsTheMemory() throws {
        let wasm = try wat2wasm("""
        (module
          (import "env" "twice" (func $twice (param i32) (result i32)))
          (memory (export "memory") 1)
          (data (i32.const 16) "dawn")
          (func (export "run") (param i32) (result i32)
            (i32.store8 (i32.const 20) (i32.const 33))
            (call $twice (local.get 0))))
        """)
        let module = try parseWasm(bytes: wasm)
        let engine = Engine()
        let store = Store(engine: engine)
        var seen = ""
        var imports = Imports()
        imports.define(module: "env", name: "twice", Function(store: store, parameters: [.i32], results: [.i32]) { caller, args in
            let memory = caller.instance!.exports[memory: "memory"]!
            seen = memory.withUnsafeMutableBufferPointer(offset: 16, count: 5) { String(decoding: $0, as: UTF8.self) }
            return [.i32(args[0].i32 * 2)]
        })
        let instance = try module.instantiate(store: store, imports: imports)
        let result = try instance.exports[function: "run"]!([.i32(21)])
        #expect(result == [.i32(42)])
        #expect(seen == "dawn!")
    }
}
