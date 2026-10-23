import SwiftUI
import WebKit

/// The sign-in page of a source in a web view. Done gives the cookies of the site and the values of the
/// keys of its local storage that the source reads. The cookies also go to the session of the sources.
struct SignInSheet: View {
    let url: URL
    let storageKeys: [String]
    let onClose: ((cookies: [String: String], storage: [String: String])?) -> Void
    @State private var page = SignInPage()

    var body: some View {
        NavigationStack {
            SignInWebView(url: url, page: page)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.host ?? "Sign in")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onClose(nil) }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { Task { onClose(await page.result(for: url.host ?? "", keys: storageKeys)) } }
                    }
                }
        }
    }

    /// Removes the cookies of a site from the web views and from the session of the sources, at a sign-out.
    @MainActor
    static func removeCookies(of host: String) async {
        func matches(_ cookie: HTTPCookie) -> Bool { host.hasSuffix(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) }
        let store = WKWebsiteDataStore.default().httpCookieStore
        for cookie in await store.allCookies() where matches(cookie) { await store.deleteCookie(cookie) }
        for cookie in HTTPCookieStorage.shared.cookies ?? [] where matches(cookie) { HTTPCookieStorage.shared.deleteCookie(cookie) }
    }
}

/// The web view of the sheet, so that Done can read the local storage of its page.
@MainActor @Observable final class SignInPage {
    @ObservationIgnored weak var view: WKWebView?

    func result(for host: String, keys: [String]) async -> (cookies: [String: String], storage: [String: String]) {
        var cookies: [String: String] = [:]
        for cookie in await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        where host.hasSuffix(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) {
            cookies[cookie.name] = cookie.value
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        var storage: [String: String] = [:]
        for key in keys {
            let script = "localStorage.getItem(\(Self.quoted(key)))"
            if let value = try? await view?.evaluateJavaScript(script) as? String { storage[key] = value }
        }
        return (cookies, storage)
    }

    private static func quoted(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }
}

private struct SignInWebView: UIViewRepresentable {
    let url: URL
    let page: SignInPage

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.customUserAgent = Network.userAgent
        view.load(URLRequest(url: url))
        page.view = view
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}
