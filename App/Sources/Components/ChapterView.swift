import SwiftUI
import WebKit

/// One chapter of a novel in a web view. The scripts of the book do not run.
/// The scripts of the app run in their own world: they apply the style, keep the place, and report taps.
struct ChapterView: UIViewRepresentable {
    let file: URL
    let folder: URL
    let css: String
    /// The place to go to when the chapter opens, from 0 to 1.
    let start: Double
    let onPosition: (Double) -> Void
    let onTap: () -> Void
    /// A link to another file of the book.
    let onLink: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let controller = configuration.userContentController
        controller.add(context.coordinator, contentWorld: .defaultClient, name: "reader")
        controller.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.load(in: view)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let old = context.coordinator.parent
        context.coordinator.parent = self
        if old.file != file {
            context.coordinator.load(in: view)
        } else if old.css != css {
            context.coordinator.applyStyle(in: view, keepPlace: true)
        }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    /// Reports the place on each scroll and each tap that is not on a link.
    private static let script = """
    (function () {
      // A chapter with no viewport is laid out at 980 points, so the text is too small.
      let viewport = document.querySelector('meta[name=viewport]');
      if (!viewport) { viewport = document.createElement('meta'); viewport.name = 'viewport'; (document.head || document.documentElement).appendChild(viewport); }
      viewport.content = 'width=device-width, initial-scale=1, viewport-fit=cover';
      let timer = null;
      function place() {
        const max = document.documentElement.scrollHeight - window.innerHeight;
        return max > 0 ? Math.min(Math.max(window.scrollY / max, 0), 1) : 1;
      }
      window.addEventListener('scroll', function () {
        if (timer) return;
        timer = setTimeout(function () { timer = null; window.webkit.messageHandlers.reader.postMessage({ position: place() }); }, 250);
      }, { passive: true });
      document.addEventListener('click', function (event) {
        if (event.target.closest('a')) return;
        window.webkit.messageHandlers.reader.postMessage({ tap: true });
      });
    })();
    """

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: ChapterView

        init(_ parent: ChapterView) { self.parent = parent }

        func load(in view: WKWebView) {
            view.alpha = 0
            view.loadFileURL(parent.file, allowingReadAccessTo: parent.folder)
        }

        func applyStyle(in view: WKWebView, keepPlace: Bool) {
            let css = parent.css.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`")
            let js = """
            (function () {
              const max = document.documentElement.scrollHeight - window.innerHeight;
              const place = max > 0 ? window.scrollY / max : 0;
              let style = document.getElementById('asabunko-style');
              if (!style) { style = document.createElement('style'); style.id = 'asabunko-style'; document.head.appendChild(style); }
              style.textContent = `\(css)`;
              const target = \(keepPlace ? "place" : String(parent.start));
              requestAnimationFrame(function () {
                window.scrollTo(0, target * (document.documentElement.scrollHeight - window.innerHeight));
              });
            })();
            """
            view.evaluateJavaScript(js, in: nil, in: .defaultClient) { _ in
                UIView.animate(withDuration: 0.2) { view.alpha = 1 }
            }
        }

        func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
            applyStyle(in: view, keepPlace: false)
        }

        func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType == .linkActivated, let url = action.request.url else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            if url.isFileURL {
                // A link in the same chapter only moves the page.
                if url.path == parent.file.path, let fragment = url.fragment {
                    let id = fragment.replacingOccurrences(of: "'", with: "\\'")
                    view.evaluateJavaScript("document.getElementById('\(id)')?.scrollIntoView()", in: nil, in: .defaultClient)
                } else {
                    parent.onLink(url)
                }
            } else if url.scheme == "http" || url.scheme == "https" {
                UIApplication.shared.open(url)
            }
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            if let position = body["position"] as? Double { parent.onPosition(position) }
            if body["tap"] != nil { parent.onTap() }
        }
    }
}
