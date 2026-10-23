import Foundation
import WebKit

/// `Application.executeInWebView` of Paperback: a page of HTML in a hidden web view, with the cookies of the
/// extension. When the page has loaded, the script of the extension runs as the body of an async function, and
/// its result goes back with the cookies of the web view.
enum PaperbackWebView {
    struct Input: Decodable {
        struct Cookie: Decodable { let name: String; let value: String; let domain: String?; let path: String? }
        let html: String
        let baseUrl: String
        let userAgent: String?
        let inject: String
        let cookies: [Cookie]
    }

    /// The time for the load of the page, and then for the script to give a result that is not empty.
    static let loadTime: TimeInterval = 20
    static let resultTime: TimeInterval = 15

    static func run(_ json: String) async throws -> String {
        let input = try JSONDecoder().decode(Input.self, from: Data(json.utf8))
        guard let base = URL(string: input.baseUrl) else { throw JSRuntimeError.script("The base URL of the web view is not correct.") }
        return try await execute(input, base: base)
    }

    /// The answer for the script: the result and the cookies, as JSON.
    private static func answer(_ result: Any?, _ cookies: [HTTPCookie]) throws -> String {
        let answer: [String: Any] = [
            "result": result ?? NSNull(),
            "cookies": cookies.map { cookie in
                var item: [String: Any] = ["name": cookie.name, "value": cookie.value, "domain": cookie.domain, "path": cookie.path]
                if let date = cookie.expiresDate { item["expires"] = date.timeIntervalSince1970 * 1000 }
                return item
            },
        ]
        let data = try JSONSerialization.data(withJSONObject: answer, options: .fragmentsAllowed)
        return String(decoding: data, as: UTF8.self)
    }

    @MainActor
    private static func execute(_ input: Input, base: URL) async throws -> String {
        let configuration = WKWebViewConfiguration()
        // Each call has its own store, so the cookies of the extension do not mix with the cookies of other pages.
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        view.customUserAgent = input.userAgent
        let store = configuration.websiteDataStore.httpCookieStore
        for cookie in input.cookies {
            let properties: [HTTPCookiePropertyKey: Any] = [
                .name: cookie.name, .value: cookie.value, .path: cookie.path ?? "/", .domain: cookie.domain ?? base.host ?? "",
            ]
            if let made = HTTPCookie(properties: properties) { await store.setCookie(made) }
        }
        let loader = Loader()
        view.navigationDelegate = loader
        view.loadHTMLString(input.html, baseURL: base)
        try await loader.wait(seconds: loadTime)

        // A page can set its value some time after the load, so an empty result asks again until the time ends.
        let end = Date().addingTimeInterval(resultTime)
        var result: Any?
        repeat {
            result = try await view.callAsyncJavaScript(input.inject, arguments: [:], contentWorld: .page)
            if let value = result, !(value is NSNull) { break }
            try await Task.sleep(for: .milliseconds(300))
        } while Date() < end
        let cookies = await store.allCookies()
        view.navigationDelegate = nil
        return try answer(result, cookies)
    }

    /// Waits for the end of the load of the page.
    @MainActor
    private final class Loader: NSObject, WKNavigationDelegate {
        private var finished = false
        private var failure: Error?

        func wait(seconds: TimeInterval) async throws {
            let end = Date().addingTimeInterval(seconds)
            while !finished && failure == nil && Date() < end { try await Task.sleep(for: .milliseconds(50)) }
            if let failure { throw failure }
            if !finished { throw JSRuntimeError.script("The page of the web view did not load.") }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished = true }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failure = error }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failure = error }
    }
}
