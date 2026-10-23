import Foundation
import JavaScriptCore
import WasmKit
import WebKit

/// A JavaScript context of the js module, in JavaScriptCore.
final class AidokuScript {
    let context = JSContext()!

    /// The result of a script as text, or nil when the script throws or gives nothing.
    func evaluate(_ script: String) -> String? {
        context.exception = nil
        let value = context.evaluateScript(script)
        guard context.exception == nil, let value, !value.isUndefined, !value.isNull else { return nil }
        return value.toString()
    }

    /// The result of a script that can give a promise. JavaScriptCore runs the jobs of the promise
    /// when the script ends, so a promise with no timer has its value then.
    func evaluateAsync(_ script: String) -> String? {
        context.exception = nil
        context.setObject(script, forKeyedSubscript: "__aidokuScript" as NSString)
        context.evaluateScript("""
        globalThis.__aidokuResult = undefined;
        Promise.resolve((0, eval)(globalThis.__aidokuScript)).then(
          (v) => { globalThis.__aidokuResult = { ok: v === undefined || v === null ? null : String(v) }; },
          (e) => { globalThis.__aidokuResult = { error: String(e) }; });
        """)
        guard let result = context.objectForKeyedSubscript("__aidokuResult"), result.isObject,
              let ok = result.objectForKeyedSubscript("ok"), !ok.isUndefined, !ok.isNull
        else { return nil }
        return ok.toString()
    }

    func global(_ name: String) -> String? {
        guard let value = context.objectForKeyedSubscript(name), !value.isUndefined, !value.isNull else { return nil }
        return value.toString()
    }
}

/// A web view of the js module. It has no window. The source queue waits while the main thread works.
final class AidokuWebView: NSObject, WKNavigationDelegate, @unchecked Sendable {
    private var view: WKWebView!
    private let loaded = DispatchSemaphore(value: 0)
    private var loading = false
    private let lock = NSLock()

    override init() {
        super.init()
        Self.onMain {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .default()
            view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
            view.navigationDelegate = self
        }
    }

    static func onMain<T>(_ body: () -> T) -> T {
        Thread.isMainThread ? body() : DispatchQueue.main.sync(execute: body)
    }

    private func start() {
        lock.withLock { loading = true }
    }

    func load(_ request: URLRequest) {
        start()
        Self.onMain { _ = view.load(request) }
    }

    func loadHTML(_ html: String, base: URL?) {
        start()
        Self.onMain { _ = view.loadHTMLString(html, baseURL: base) }
    }

    /// Waits until the page ends its load. Gives false after the time limit.
    func waitForLoad(timeout: TimeInterval = 60) -> Bool {
        guard lock.withLock({ loading }) else { return true }
        return loaded.wait(timeout: .now() + timeout) == .success
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish() }

    private func finish() {
        let wasLoading = lock.withLock { () -> Bool in
            defer { loading = false }
            return loading
        }
        if wasLoading { loaded.signal() }
    }

    /// The result of a script in the page as text.
    func evaluate(_ script: String, async: Bool) -> String? {
        let done = DispatchSemaphore(value: 0)
        let box = Box()
        Self.onMain {
            let handle: (Result<Any, Error>) -> Void = { outcome in
                if case let .success(value) = outcome, !(value is NSNull) { box.text = "\(value)" }
                done.signal()
            }
            if async {
                view.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page, completionHandler: handle)
            } else {
                view.evaluateJavaScript(script) { value, error in
                    if let error { handle(.failure(error)) } else { handle(.success(value ?? NSNull())) }
                }
            }
        }
        _ = done.wait(timeout: .now() + 60)
        return box.text
    }

    func addUserScript(_ script: String, atEnd: Bool, mainFrameOnly: Bool) {
        Self.onMain {
            view.configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: atEnd ? .atDocumentEnd : .atDocumentStart, forMainFrameOnly: mainFrameOnly))
        }
    }

    func setRuleList(_ json: String) -> Bool {
        let done = DispatchSemaphore(value: 0)
        let box = Box()
        Self.onMain {
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "aidoku.\(UUID().uuidString)", encodedContentRuleList: json) { [view] list, _ in
                if let list, let view {
                    view.configuration.userContentController.add(list)
                    box.text = "ok"
                }
                done.signal()
            }
        }
        _ = done.wait(timeout: .now() + 30)
        return box.text != nil
    }

    func cookies() -> [HTTPCookie] {
        let done = DispatchSemaphore(value: 0)
        let box = Box()
        Self.onMain {
            view.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                box.cookies = cookies
                done.signal()
            }
        }
        _ = done.wait(timeout: .now() + 30)
        return box.cookies
    }

    func deleteCookies(name: String?, value: String?, domain: String?) {
        let store = Self.onMain { view.configuration.websiteDataStore.httpCookieStore }
        for cookie in cookies() where (name == nil || cookie.name == name) && (value == nil || cookie.value == value) && (domain == nil || cookie.domain == domain) {
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { store.delete(cookie) { done.signal() } }
            _ = done.wait(timeout: .now() + 10)
        }
    }

    private final class Box: @unchecked Sendable {
        var text: String?
        var cookies: [HTTPCookie] = []
    }
}

extension AidokuHost {
    func installScript(define: (String, String, [ValueType], [ValueType], @escaping ([Value]) throws -> [Value]) -> Void) {
        let i32 = Self.i32, result = Self.result
        func script(_ rid: Int32) -> AidokuScript? { if case let .script(script)? = item(rid) { return script }; return nil }
        func web(_ rid: Int32) -> AidokuWebView? { if case let .webView(view)? = item(rid) { return view }; return nil }

        define("js", "context_create", [], [.i32]) { [unowned self] _ in result(add(.script(AidokuScript()))) }
        define("js", "context_eval", [.i32, .i32, .i32], [.i32]) { [unowned self] a in
            guard let script = script(i32(a[0])) else { return result(-2) }
            guard let text = script.evaluate(string(i32(a[1]), i32(a[2]))) else { return result(-1) }
            return result(addString(text))
        }
        define("js", "context_eval_async", [.i32, .i32, .i32], [.i32]) { [unowned self] a in
            guard let script = script(i32(a[0])) else { return result(-2) }
            guard let text = script.evaluateAsync(string(i32(a[1]), i32(a[2]))) else { return result(-1) }
            return result(addString(text))
        }
        define("js", "context_get", [.i32, .i32, .i32], [.i32]) { [unowned self] a in
            guard let script = script(i32(a[0])) else { return result(-2) }
            guard let text = script.global(string(i32(a[1]), i32(a[2]))) else { return result(-1) }
            return result(addString(text))
        }

        define("js", "webview_create", [], [.i32]) { [unowned self] _ in result(add(.webView(AidokuWebView()))) }
        define("js", "webview_set_rule_list", [.i32, .i32, .i32], [.i32]) { [unowned self] a in
            guard let view = web(i32(a[0])) else { return result(-2) }
            return result(view.setRuleList(string(i32(a[1]), i32(a[2]))) ? 0 : -6)
        }
        define("js", "webview_load", [.i32, .i32], [.i32]) { [unowned self] a in
            guard let view = web(i32(a[0])) else { return result(-2) }
            guard case let .request(request)? = item(i32(a[1])), let url = request.url else { return result(-5) }
            var urlRequest = URLRequest(url: url, timeoutInterval: request.timeout)
            urlRequest.httpMethod = request.method
            urlRequest.httpBody = request.body
            for (key, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: key) }
            view.load(urlRequest)
            return result(0)
        }
        define("js", "webview_load_html", [.i32, .i32, .i32, .i32, .i32], [.i32]) { [unowned self] a in
            guard let view = web(i32(a[0])) else { return result(-2) }
            let base = i32(a[4]) > 0 ? URL(string: string(i32(a[3]), i32(a[4]))) : nil
            view.loadHTML(string(i32(a[1]), i32(a[2])), base: base)
            return result(0)
        }
        define("js", "webview_wait_for_load", [.i32], [.i32]) { a in
            guard let view = web(i32(a[0])) else { return result(-2) }
            return result(view.waitForLoad() ? 0 : -1)
        }
        define("js", "webview_eval", [.i32, .i32, .i32], [.i32]) { [unowned self] a in
            guard let view = web(i32(a[0])) else { return result(-2) }
            guard let text = view.evaluate(string(i32(a[1]), i32(a[2])), async: false) else { return result(-1) }
            return result(addString(text))
        }
        define("js", "webview_eval_async", [.i32, .i32, .i32], [.i32]) { [unowned self] a in
            guard let view = web(i32(a[0])) else { return result(-2) }
            guard let text = view.evaluate(string(i32(a[1]), i32(a[2])), async: true) else { return result(-1) }
            return result(addString(text))
        }
        define("js", "webview_add_user_script", [.i32, .i32, .i32, .i32, .i32], [.i32]) { [unowned self] a in
            guard let view = web(i32(a[0])) else { return result(-2) }
            view.addUserScript(string(i32(a[1]), i32(a[2])), atEnd: i32(a[3]) != 0, mainFrameOnly: i32(a[4]) != 0)
            return result(0)
        }
        define("js", "webview_get_cookies", [.i32], [.i32]) { [unowned self] a in
            guard let view = web(i32(a[0])) else { return result(-2) }
            var w = PostcardWriter()
            w.list(view.cookies()) { w, cookie in
                w.string(cookie.name)
                w.string(cookie.value)
                w.option(cookie.expiresDate.map { Int64($0.timeIntervalSince1970) }) { $0.signed($1) }
                w.string(cookie.domain)
                w.string(cookie.path)
                w.bool(cookie.isSecure)
                w.bool(cookie.isHTTPOnly)
            }
            return result(add(.bytes(w.data)))
        }
        define("js", "webview_delete_cookie", [.i32, .i32, .i32, .i32, .i32, .i32, .i32], [.i32]) { [unowned self] a in
            guard let view = web(i32(a[0])) else { return result(-2) }
            // A name length of 0xFFFFFFFF means all cookies.
            let all = UInt32(bitPattern: i32(a[2])) == 0xFFFF_FFFF
            view.deleteCookies(name: all ? nil : string(i32(a[1]), i32(a[2])),
                               value: all || i32(a[4]) <= 0 ? nil : string(i32(a[3]), i32(a[4])),
                               domain: all || i32(a[6]) <= 0 ? nil : string(i32(a[5]), i32(a[6])))
            return result(0)
        }
    }
}
