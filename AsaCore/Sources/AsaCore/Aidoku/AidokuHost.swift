import Foundation
import SwiftSoup
import WasmKit

/// The settings of one Aidoku source, as the postcard bytes of each value. They stay in a file.
final class AidokuDefaults: @unchecked Sendable {
    private var values: [String: Data]
    private let file: URL?

    init(file: URL?, initial: [String: Data]) {
        self.file = file
        let saved = file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: Data].self, from: $0) } ?? [:]
        values = initial.merging(saved) { _, saved in saved }
    }

    /// The source reads the values on its queue, and the settings screen reads them on the main thread.
    private let lock = NSLock()

    subscript(key: String) -> Data? {
        get { lock.withLock { values[key] } }
        set {
            lock.withLock {
                values[key] = newValue
                if let file, let data = try? JSONEncoder().encode(values) { try? data.write(to: file, options: .atomic) }
            }
        }
    }
}

/// One Aidoku source in WasmKit, with the imports of aidoku-rs: env, std, net, html, and defaults.
/// js and canvas are stubs, so a source that needs a web view or the drawing of images fails cleanly.
/// All calls go through one queue, because the imports block while they wait for the network.
final class AidokuHost: @unchecked Sendable {
    enum Item {
        case bytes(Data)
        case request(Request)
        case document(Document)
        case element(Element)
        case elements(Elements)
        case node(Node)
        case nodes([Node])
    }

    final class Request {
        var method = "GET"
        var url: URL?
        var headers: [String: String] = [:]
        var body: Data?
        var timeout: Double = 30
        var response: (status: Int, url: URL?, headers: [String: String], body: Data)?
    }

    enum Failure: Error, LocalizedError, Equatable {
        case trap(String)
        case code(Int32)
        case message(String)
        case missing(String)

        var errorDescription: String? {
            switch self {
            case let .trap(text): "The source stopped: \(text)"
            case let .code(code): "The source failed with the code \(code)."
            case let .message(text): text
            case let .missing(name): "The source has no \(name)."
            }
        }
    }

    let queue: DispatchQueue
    private let fetcher: Fetcher
    let defaults: AidokuDefaults
    private var items: [Int32: Item] = [:]
    private var next: Int32 = 1
    private var instance: Instance!
    private(set) var exports: Set<String> = []
    private var printed: [String] = []

    init(name: String, wasm: Data, defaults: AidokuDefaults, fetcher: @escaping Fetcher) throws {
        self.queue = DispatchQueue(label: "io.github.stivengjekaj.asabunko.aidoku.\(name)")
        self.fetcher = fetcher
        self.defaults = defaults
        let bytes = [UInt8](wasm)
        let module = try parseWasm(bytes: bytes)
        let store = Store(engine: Engine())
        var imports = Imports()
        var defined = Set<String>()
        func define(_ module: String, _ name: String, _ parameters: [ValueType], _ results: [ValueType], _ body: @escaping ([Value]) throws -> [Value]) {
            imports.define(module: module, name: name, Function(store: store, parameters: parameters, results: results) { _, args in try body(args) })
            defined.insert("\(module).\(name)")
        }
        let declared = WasmImports.functions(in: bytes)
        installImports(declared: declared, define: define)
        // An import of the module that the host does not have gets a stub that gives an error.
        for function in declared where !defined.contains("\(function.module).\(function.name)") {
            let results = function.results
            imports.define(module: function.module, name: function.name, Function(store: store, parameters: function.parameters, results: results) { _, _ in
                results.map { type -> Value in
                    switch type {
                    case .i64: .i64(UInt64(bitPattern: -1))
                    case .f32: .f32(Float(-1).bitPattern)
                    case .f64: .f64(Double(-1).bitPattern)
                    default: .i32(UInt32(bitPattern: -1))
                    }
                }
            })
        }
        instance = try module.instantiate(store: store, imports: imports)
        exports = Set(module.exports.map(\.name))
        try queue.sync { _ = try invoke("start", []) }
    }

    // MARK: Values and memory

    static func i32(_ value: Value) -> Int32 {
        if case let .i32(bits) = value { return Int32(bitPattern: bits) }
        return 0
    }

    static func f64(_ value: Value) -> Double {
        if case let .f64(bits) = value { return Double(bitPattern: bits) }
        return 0
    }

    static func f32(_ value: Value) -> Float {
        if case let .f32(bits) = value { return Float(bitPattern: bits) }
        return 0
    }

    static func result(_ value: Int32) -> [Value] { [.i32(UInt32(bitPattern: value))] }

    private var memory: Memory { instance.exports[memory: "memory"]! }

    func read(_ pointer: Int32, _ count: Int32) -> Data {
        guard count > 0, pointer >= 0, Int(pointer) + Int(count) <= memory.byteCount else { return Data() }
        return memory.withUnsafeMutableBufferPointer(offset: UInt(pointer), count: Int(count)) { Data($0) }
    }

    func string(_ pointer: Int32, _ count: Int32) -> String {
        String(decoding: read(pointer, count), as: UTF8.self)
    }

    @discardableResult
    func write(_ data: Data, at pointer: Int32) -> Bool {
        guard pointer >= 0, Int(pointer) + data.count <= memory.byteCount else { return false }
        memory.withUnsafeMutableBufferPointer(offset: UInt(pointer), count: data.count) { buffer in
            data.copyBytes(to: buffer)
        }
        return true
    }

    func int32(at pointer: Int32) -> Int32 {
        let data = read(pointer, 4)
        guard data.count == 4 else { return 0 }
        return data.withUnsafeBytes { Int32(littleEndian: $0.loadUnaligned(as: Int32.self)) }
    }

    /// The payload of a buffer of the source: [length][capacity][postcard], where the length counts the 8 bytes of the head.
    func encodedBuffer(at pointer: Int32) -> Data {
        let total = int32(at: pointer)
        guard total >= 8 else { return Data() }
        return read(pointer + 8, total - 8)
    }

    // MARK: Store of the host

    func add(_ item: Item) -> Int32 {
        let rid = next
        next += 1
        items[rid] = item
        return rid
    }

    func item(_ rid: Int32) -> Item? { items[rid] }

    func destroy(_ rid: Int32) { items[rid] = nil }

    func addString(_ text: String) -> Int32 { add(.bytes(Data(text.utf8))) }

    // MARK: Calls of exports

    /// Calls an export with the arguments. The caller is on the queue.
    func invoke(_ name: String, _ arguments: [Value]) throws -> [Value] {
        guard let function = instance.exports[function: name] else { throw Failure.missing(name) }
        printed = []
        do {
            return try function(arguments)
        } catch {
            throw Failure.trap(printed.last ?? String(describing: error))
        }
    }

    /// Calls an export that gives a result buffer, and gives the postcard payload.
    /// Each argument that is Data goes into the store of the host for the call, and is destroyed after it.
    func call(_ name: String, _ arguments: [Any]) throws -> Data {
        var made: [Int32] = []
        defer { for rid in made { destroy(rid) } }
        let values: [Value] = arguments.map { argument in
            switch argument {
            case let data as Data:
                let rid = add(.bytes(data))
                made.append(rid)
                return .i32(UInt32(bitPattern: rid))
            case let number as Int32: return .i32(UInt32(bitPattern: number))
            case let number as Int: return .i32(UInt32(bitPattern: Int32(truncatingIfNeeded: number)))
            case let flag as Bool: return .i32(flag ? 1 : 0)
            default: return .i32(UInt32(bitPattern: -1))
            }
        }
        let pointer = Self.i32(try invoke(name, values).first ?? .i32(0))
        if pointer < 0 { throw Failure.code(pointer) }
        let mark = int32(at: pointer)
        defer { _ = try? invoke("free_result", [.i32(UInt32(bitPattern: pointer))]) }
        if mark == -1 {
            let total = int32(at: pointer + 8)
            throw Failure.message(string(pointer + 12, max(total - 12, 0)))
        }
        return read(pointer + 8, max(mark - 8, 0))
    }

    // MARK: The network, which blocks the queue of the source

    func send(_ request: Request) -> Int32 {
        guard let url = request.url else { return -4 }
        var urlRequest = URLRequest(url: url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: key) }
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()
        let fetcher = fetcher
        Task.detached {
            do { box.value = .success(try await fetcher(urlRequest)) } catch { box.value = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        guard case let .success((data, response))? = box.value else { return -10 }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields { headers["\(key)"] = "\(value)" }
        request.response = (response.statusCode, response.url ?? url, headers, data)
        return 0
    }

    private final class ResultBox: @unchecked Sendable {
        var value: Result<(Data, HTTPURLResponse), Error>?
    }

    // MARK: Imports

    private func installImports(declared: [WasmImports.Function], define: (String, String, [ValueType], [ValueType], @escaping ([Value]) throws -> [Value]) -> Void) {
        let i32 = Self.i32
        let result = Self.result

        // env
        define("env", "abort", [], []) { [unowned self] _ in printed.append("abort"); return [] }
        define("env", "print", [.i32, .i32], []) { [unowned self] a in
            let text = string(i32(a[0]), i32(a[1]))
            printed.append(text)
            #if DEBUG
            print("[aidoku] \(text.prefix(400))")
            #endif
            return []
        }
        define("env", "sleep", [.i32], []) { a in Thread.sleep(forTimeInterval: Double(min(max(i32(a[0]), 0), 10))); return [] }
        define("env", "send_partial_result", [.i32], []) { _ in [] }

        // std
        define("std", "destroy", [.i32], []) { [unowned self] a in destroy(i32(a[0])); return [] }
        define("std", "buffer_len", [.i32], [.i32]) { [unowned self] a in
            guard case let .bytes(data)? = item(i32(a[0])) else { return result(-1) }
            return result(Int32(data.count))
        }
        define("std", "read_buffer", [.i32, .i32, .i32], [.i32]) { [unowned self] a in
            guard case let .bytes(data)? = item(i32(a[0])) else { return result(-1) }
            let count = Int(i32(a[2]))
            guard count <= data.count, write(data.prefix(count), at: i32(a[1])) else { return result(-3) }
            return result(0)
        }
        define("std", "current_date", [], [.f64]) { _ in [.f64(Date().timeIntervalSince1970.rounded(.down).bitPattern)] }
        define("std", "utc_offset", [], [.i64]) { _ in [.i64(UInt64(bitPattern: Int64(-TimeZone.current.secondsFromGMT())))] }
        define("std", "parse_date", [.i32, .i32, .i32, .i32, .i32, .i32, .i32, .i32], [.f64]) { [unowned self] a in
            let text = string(i32(a[0]), i32(a[1]))
            let format = string(i32(a[2]), i32(a[3]))
            let locale = i32(a[5]) > 0 ? string(i32(a[4]), i32(a[5])) : ""
            let zone = i32(a[7]) > 0 ? string(i32(a[6]), i32(a[7])) : "UTC"
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: locale.isEmpty ? "en_US_POSIX" : locale)
            formatter.timeZone = zone == "current" ? .current : (TimeZone(identifier: zone) ?? TimeZone(identifier: "UTC"))
            guard let date = formatter.date(from: text) else { return [.f64(Double(-5).bitPattern)] }
            return [.f64(date.timeIntervalSince1970.bitPattern)]
        }

        // defaults
        define("defaults", "get", [.i32, .i32], [.i32]) { [unowned self] a in
            guard let value = defaults[string(i32(a[0]), i32(a[1]))] else { return result(-2) }
            return result(add(.bytes(value)))
        }
        define("defaults", "set", [.i32, .i32, .i32, .i32], [.i32]) { [unowned self] a in
            let key = string(i32(a[0]), i32(a[1]))
            if i32(a[2]) == 6 {
                defaults[key] = nil
            } else {
                defaults[key] = encodedBuffer(at: i32(a[3]))
            }
            return result(0)
        }

        installNet(define: define)
        installHTML(define: define)
    }

    private func installNet(define: (String, String, [ValueType], [ValueType], @escaping ([Value]) throws -> [Value]) -> Void) {
        let i32 = Self.i32
        let result = Self.result
        let methods = ["GET", "POST", "PUT", "HEAD", "DELETE", "PATCH", "OPTIONS", "CONNECT", "TRACE"]
        func request(_ rid: Int32) -> Request? {
            if case let .request(request)? = item(rid) { return request }
            return nil
        }
        define("net", "init", [.i32], [.i32]) { [unowned self] a in
            let method = Int(i32(a[0]))
            guard methods.indices.contains(method) else { return result(-3) }
            let request = Request()
            request.method = methods[method]
            return result(add(.request(request)))
        }
        define("net", "set_url", [.i32, .i32, .i32], [.i32]) { [unowned self] a in
            guard let request = request(i32(a[0])) else { return result(-1) }
            guard let url = URL(lenient: string(i32(a[1]), i32(a[2]))) else { return result(-4) }
            request.url = url
            return result(0)
        }
        define("net", "set_header", [.i32, .i32, .i32, .i32, .i32], [.i32]) { [unowned self] a in
            guard let request = request(i32(a[0])) else { return result(-1) }
            request.headers[string(i32(a[1]), i32(a[2]))] = string(i32(a[3]), i32(a[4]))
            return result(0)
        }
        define("net", "set_body", [.i32, .i32, .i32], [.i32]) { [unowned self] a in
            guard let request = request(i32(a[0])) else { return result(-1) }
            request.body = read(i32(a[1]), i32(a[2]))
            return result(0)
        }
        define("net", "set_timeout", [.i32, .f64], [.i32]) { [unowned self] a in
            guard let request = request(i32(a[0])) else { return result(-1) }
            request.timeout = max(1, Self.f64(a[1]))
            return result(0)
        }
        define("net", "send", [.i32], [.i32]) { [unowned self] a in
            guard let request = request(i32(a[0])) else { return result(-1) }
            return result(send(request))
        }
        define("net", "send_all", [.i32, .i32], [.i32]) { [unowned self] a in
            let pointer = i32(a[0]), count = i32(a[1])
            var failed = false
            for index in 0..<max(count, 0) {
                let slot = pointer + index * 4
                let code = request(int32(at: slot)).map(send) ?? -1
                if code != 0 { failed = true }
                var little = code.littleEndian
                guard write(Data(bytes: &little, count: 4), at: slot) else { return result(-11) }
            }
            return result(failed ? -10 : 0)
        }
        define("net", "data_len", [.i32], [.i32]) { a in
            guard let response = request(i32(a[0]))?.response else { return result(-8) }
            return result(Int32(response.body.count))
        }
        define("net", "read_data", [.i32, .i32, .i32], [.i32]) { [unowned self] a in
            guard let response = request(i32(a[0]))?.response else { return result(-8) }
            let count = Int(i32(a[2]))
            guard count <= response.body.count, write(response.body.prefix(count), at: i32(a[1])) else { return result(-11) }
            return result(0)
        }
        define("net", "get_status_code", [.i32], [.i32]) { a in
            guard let response = request(i32(a[0]))?.response else { return result(-8) }
            return result(Int32(response.status))
        }
        define("net", "get_url", [.i32], [.i32]) { [unowned self] a in
            guard let response = request(i32(a[0]))?.response else { return result(-8) }
            return result(addString(response.url?.absoluteString ?? ""))
        }
        define("net", "get_header", [.i32, .i32, .i32], [.i32]) { [unowned self] a in
            guard let response = request(i32(a[0]))?.response else { return result(-8) }
            let name = string(i32(a[1]), i32(a[2])).lowercased()
            let values = response.headers.filter { $0.key.lowercased() == name }.map(\.value)
            guard !values.isEmpty else { return result(-7) }
            return result(addString(values.joined(separator: ", ")))
        }
        define("net", "html", [.i32], [.i32]) { [unowned self] a in
            guard let response = request(i32(a[0]))?.response else { return result(-8) }
            guard let document = try? SwiftSoup.parse(TextDecoding.decode(response.body), response.url?.absoluteString ?? "") else { return result(-5) }
            return result(add(.document(document)))
        }
        define("net", "get_image", [.i32], [.i32]) { _ in result(-12) }
        define("net", "set_rate_limit", [.i32, .i32, .i32], []) { _ in [] }
    }
}
