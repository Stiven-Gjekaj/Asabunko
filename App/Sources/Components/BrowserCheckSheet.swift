import AsaCore
import SwiftUI
import WebKit

/// A banner at the bottom of the app when a site asks for a check in a browser.
struct BrowserCheckBanner: View {
    @State private var checks = BrowserChecks.shared
    @State private var opened: URL?

    var body: some View {
        Group {
            if let url = checks.pending {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.shield").font(.system(size: 20)).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(url.host ?? "A site") asks for a check").font(Karla.font(15, .bold)).lineLimit(1)
                        Text("Open the page and pass the check once.").font(Karla.font(13)).foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 4)
                    Button("Open") { opened = url }.buttonStyle(PillButtonStyle())
                    Button { checks.pending = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close the check")
                }
                .padding(.leading, 16)
                .padding(.vertical, 8)
                .background(Palette.surfaceHigh, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(Palette.outline, lineWidth: 0.5))
                .padding(.horizontal, 12)
                .padding(.bottom, 60)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: checks.pending)
        .sheet(item: $opened) { url in
            BrowserCheckSheet(url: url) { passed in
                if passed, let host = url.host { checks.markPassed(host) }
                opened = nil
            }
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// The page of a site in a web view, with the user agent of the app. When the cookie of the check
/// comes, the cookies of the site go to the session of the sources, and the sheet closes.
struct BrowserCheckSheet: View {
    let url: URL
    let onClose: (Bool) -> Void
    @State private var title = ""

    var body: some View {
        NavigationStack {
            CheckWebView(url: url, title: $title) { onClose(true) }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title.isEmpty ? (url.host ?? "Check") : title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onClose(false) }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            Task {
                                await CheckWebView.copyCookies(for: url.host ?? "")
                                onClose(true)
                            }
                        }
                    }
                }
        }
    }
}

private struct CheckWebView: UIViewRepresentable {
    let url: URL
    @Binding var title: String
    let onPassed: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.customUserAgent = Network.userAgent
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Copies the cookies of the web view to the cookie store of the session of the sources.
    @MainActor
    static func copyCookies(for host: String) async {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        for cookie in cookies where host.hasSuffix(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: CheckWebView
        private var done = false

        init(_ parent: CheckWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.title = webView.title ?? ""
            // The check can end after some loads of the page, so each load looks for the cookie.
            Task { @MainActor in
                let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                let host = parent.url.host ?? ""
                guard !done, BrowserCheck.passed(cookies, host: host) else { return }
                done = true
                await CheckWebView.copyCookies(for: host)
                parent.onPassed()
            }
        }
    }
}
