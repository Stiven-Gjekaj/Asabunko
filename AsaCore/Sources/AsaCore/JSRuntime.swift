import Foundation
import JavaScriptCore

/// Makes the network requests of a JavaScript source. The app gives URLSession, and a test gives fixed answers.
public typealias Fetcher = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

public enum JSRuntimeError: Error, Equatable, LocalizedError {
    /// The script threw an error, with its message.
    case script(String)
    /// The script gave no answer in the time.
    case timeout
    /// The answer was not the JSON that the app expected.
    case badAnswer(String)

    public var errorDescription: String? {
        switch self {
        case let .script(message): "The source failed: \(message)"
        case .timeout: "The source did not answer in time."
        case let .badAnswer(message): "The source gave an answer that Asabunko cannot read: \(message)"
        }
    }
}

/// One JavaScript context with the web functions that the sources need: fetch, timers,
/// TextDecoder, and the libraries of libraries.js. All work on the context is on one queue.
public final class JSRuntime: @unchecked Sendable {
    private let queue: DispatchQueue
    private let context: JSContext
    private let fetcher: Fetcher
    private var lastError: String?
    public var timeout: TimeInterval = 60

    public init(name: String, fetcher: @escaping Fetcher) throws {
        self.queue = DispatchQueue(label: "io.github.stivengjekaj.asabunko.js.\(name)")
        self.fetcher = fetcher
        guard let context = JSContext() else { throw JSRuntimeError.script("No JavaScript context") }
        self.context = context
        context.name = name
        try queue.sync {
            context.exceptionHandler = { [weak self] _, exception in
                self?.lastError = exception?.toString() ?? "unknown error"
            }
            installNatives()
            for resource in ["libraries", "host"] {
                guard let url = Bundle.module.url(forResource: resource, withExtension: "js"),
                      let script = try? String(contentsOf: url, encoding: .utf8)
                else { throw JSRuntimeError.script("No \(resource).js in the package") }
                try evaluateOnQueue(script, url: url.lastPathComponent)
            }
        }
    }

    /// Runs a script, such as the code of a plugin.
    public func evaluate(_ script: String, url: String = "source.js") throws {
        try queue.sync { try evaluateOnQueue(script, url: url) }
    }

    /// Calls the function that `function` gives, such as "plugin.popularNovels", with the arguments.
    /// The function can give a promise. The answer is its value as JSON.
    public func invoke(_ function: String, _ arguments: [Any] = []) async throws -> Data {
        let once = Once()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            queue.async { [self] in
                let resolve: @convention(block) (JSValue) -> Void = { value in
                    once.run { continuation.resume(returning: Data((value.toString() ?? "null").utf8)) }
                }
                let reject: @convention(block) (JSValue) -> Void = { value in
                    let message = value.forProperty("message").flatMap { $0.isUndefined ? nil : $0.toString() } ?? value.toString() ?? "error"
                    once.run { continuation.resume(throwing: JSRuntimeError.script(message)) }
                }
                lastError = nil
                let target = context.evaluateScript("(\(function))")
                if let error = lastError {
                    once.run { continuation.resume(throwing: JSRuntimeError.script(error)) }
                    return
                }
                let promise = context.objectForKeyedSubscript("__invoke").call(withArguments: [target as Any] + arguments)
                if let error = lastError {
                    once.run { continuation.resume(throwing: JSRuntimeError.script(error)) }
                    return
                }
                promise?.invokeMethod("then", withArguments: [JSValue(object: resolve, in: context) as Any, JSValue(object: reject, in: context) as Any])
                queue.asyncAfter(deadline: .now() + timeout) {
                    once.run { continuation.resume(throwing: JSRuntimeError.timeout) }
                }
            }
        }
    }

    /// Calls a function and decodes its answer.
    public func invoke<T: Decodable>(_ type: T.Type, _ function: String, _ arguments: [Any] = []) async throws -> T {
        let data = try await invoke(function, arguments)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw JSRuntimeError.badAnswer(String(describing: error).prefix(300).description)
        }
    }

    /// Adds a native function to the object __native of the context, such as a function of a host of an ecosystem.
    public func define(_ name: String, _ block: Any) {
        queue.sync {
            context.objectForKeyedSubscript("__native").setObject(block, forKeyedSubscript: name as NSString)
        }
    }

    /// Adds a native function that takes time, such as a page in a web view. The script calls `__native.<name>(text)`
    /// and gets a promise of the text of the answer. A thrown error rejects the promise with its message.
    public func defineAsync(_ name: String, _ handler: @escaping @Sendable (String) async throws -> String) {
        let start: @convention(block) (Int, String) -> Void = { [weak self] id, input in
            Task.detached {
                let result: Result<String, Error>
                do { result = .success(try await handler(input)) } catch { result = .failure(error) }
                self?.queue.async {
                    let done = self?.context.objectForKeyedSubscript("__asyncDone")
                    switch result {
                    case let .success(text): done?.call(withArguments: [id, NSNull(), text])
                    case let .failure(error): done?.call(withArguments: [id, error.localizedDescription, NSNull()])
                    }
                }
            }
        }
        queue.sync {
            let native = context.objectForKeyedSubscript("__native")!
            native.setObject(start, forKeyedSubscript: "__start_\(name)" as NSString)
            context.evaluateScript("""
            (function () {
              if (!globalThis.__asyncDone) {
                const waiting = {};
                let next = 0;
                globalThis.__asyncCall = (name, input) => new Promise((resolve, reject) => {
                  const id = ++next;
                  waiting[id] = { resolve, reject };
                  __native['__start_' + name](id, String(input));
                });
                globalThis.__asyncDone = (id, error, value) => {
                  const call = waiting[id];
                  delete waiting[id];
                  if (!call) return;
                  if (error === null || error === undefined) call.resolve(value); else call.reject(new Error(error));
                };
              }
              __native[\(Self.quoted(name))] = (input) => __asyncCall(\(Self.quoted(name)), input);
            })();
            """)
        }
    }

    private static func quoted(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }

    /// The bytes of a typed array or an ArrayBuffer, for a native function. The caller is on the queue of the context.
    public func bytes(of value: JSValue) -> Data { data(of: value) }

    /// A new ArrayBuffer, for the answer of a native function. The caller is on the queue of the context.
    public func makeArrayBuffer(_ data: Data) -> JSValue? { arrayBuffer(data) }

    private func evaluateOnQueue(_ script: String, url: String) throws {
        lastError = nil
        context.evaluateScript(script, withSourceURL: URL(string: url))
        if let error = lastError { throw JSRuntimeError.script(error) }
    }

    // MARK: Native functions

    private func installNatives() {
        let native = JSValue(newObjectIn: context)!
        let fetch: @convention(block) (Int, String, String, JSValue, JSValue) -> Void = { [weak self] id, url, method, headers, body in
            self?.startFetch(id: id, url: url, method: method, headers: headers, body: body)
        }
        let decode: @convention(block) (JSValue, String) -> String = { [weak self] bytes, label in
            guard let self else { return "" }
            return Self.decode(self.data(of: bytes), label: label)
        }
        let timer: @convention(block) (Int, Double) -> Void = { [weak self] id, ms in
            self?.queue.asyncAfter(deadline: .now() + ms / 1000) {
                self?.context.objectForKeyedSubscript("__timerFire").call(withArguments: [id])
            }
        }
        let log: @convention(block) (String) -> Void = { message in
            #if DEBUG
            print("[js] \(message.prefix(500))")
            #endif
        }
        native.setObject(fetch, forKeyedSubscript: "fetch" as NSString)
        native.setObject(decode, forKeyedSubscript: "decode" as NSString)
        native.setObject(timer, forKeyedSubscript: "timer" as NSString)
        native.setObject(log, forKeyedSubscript: "log" as NSString)
        context.setObject(native, forKeyedSubscript: "__native" as NSString)
    }

    private func startFetch(id: Int, url: String, method: String, headers: JSValue, body: JSValue) {
        guard let target = URL(string: url) else {
            context.objectForKeyedSubscript("__fetchDone").call(withArguments: [id, "Bad URL: \(url)"])
            return
        }
        var request = URLRequest(url: target)
        request.httpMethod = method
        for (key, value) in (headers.toDictionary() as? [String: Any]) ?? [:] {
            request.setValue("\(value)", forHTTPHeaderField: key)
        }
        if !body.isNull && !body.isUndefined { request.httpBody = data(of: body) }
        let fetcher = fetcher
        Task.detached { [weak self] in
            let result: Result<(Data, HTTPURLResponse), Error>
            do { result = .success(try await fetcher(request)) } catch { result = .failure(error) }
            self?.queue.async { self?.finishFetch(id: id, result: result) }
        }
    }

    private func finishFetch(id: Int, result: Result<(Data, HTTPURLResponse), Error>) {
        let done = context.objectForKeyedSubscript("__fetchDone")
        switch result {
        case let .failure(error):
            done?.call(withArguments: [id, error.localizedDescription])
        case let .success((data, response)):
            var headers: [String: String] = [:]
            var fields: [String: String] = [:]
            for (key, value) in response.allHeaderFields {
                headers["\(key)".lowercased()] = "\(value)"
                fields["\(key)"] = "\(value)"
            }
            // The cookies of the answer, read by Foundation, because a Set-Cookie header can hold commas.
            let url = response.url ?? URL(string: "about:blank")!
            let cookies: [[String: Any]] = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url).map { cookie in
                var item: [String: Any] = ["name": cookie.name, "value": cookie.value, "domain": cookie.domain, "path": cookie.path]
                if let expires = cookie.expiresDate { item["expires"] = expires.timeIntervalSince1970 * 1000 }
                return item
            }
            done?.call(withArguments: [id, NSNull(), response.statusCode, response.url?.absoluteString ?? "", headers, arrayBuffer(data) as Any, cookies])
        }
    }

    /// A new ArrayBuffer with a copy of the bytes.
    private func arrayBuffer(_ data: Data) -> JSValue? {
        let count = data.count
        let bytes = malloc(max(count, 1))!
        data.copyBytes(to: bytes.assumingMemoryBound(to: UInt8.self), count: count)
        var exception: JSValueRef?
        let object = JSObjectMakeArrayBufferWithBytesNoCopy(context.jsGlobalContextRef, bytes, count, { bytes, _ in free(bytes) }, nil, &exception)
        return object.map { JSValue(jsValueRef: $0, in: context) }
    }

    /// The bytes of a Uint8Array, a typed array, or an ArrayBuffer.
    private func data(of value: JSValue) -> Data {
        let ctx = context.jsGlobalContextRef
        guard let object = JSValueToObject(ctx, value.jsValueRef, nil) else { return Data() }
        var exception: JSValueRef?
        let type = JSValueGetTypedArrayType(ctx, value.jsValueRef, &exception)
        if type == kJSTypedArrayTypeArrayBuffer {
            guard let pointer = JSObjectGetArrayBufferBytesPtr(ctx, object, &exception) else { return Data() }
            return Data(bytes: pointer, count: JSObjectGetArrayBufferByteLength(ctx, object, &exception))
        }
        if type != kJSTypedArrayTypeNone {
            guard let pointer = JSObjectGetTypedArrayBytesPtr(ctx, object, &exception) else { return Data() }
            let offset = JSObjectGetTypedArrayByteOffset(ctx, object, &exception)
            return Data(bytes: pointer.advanced(by: offset), count: JSObjectGetTypedArrayByteLength(ctx, object, &exception))
        }
        return Data((value.toString() ?? "").utf8)
    }

    /// Decodes bytes with an IANA name of an encoding, such as "utf-8", "gbk", or "shift_jis".
    static func decode(_ data: Data, label: String) -> String {
        let name = label.isEmpty ? "utf-8" : label
        let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        if cf != kCFStringEncodingInvalidId, name != "utf-8", name != "utf8" {
            let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
            if let text = String(data: data, encoding: encoding) { return text }
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Runs its block one time only, from any thread.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ block: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        block()
    }
}
