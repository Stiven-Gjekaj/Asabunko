import AVFoundation
import SwiftUI
import WebKit

/// The calls of the novel reader to the page of a chapter: the sentences for the speech, the search, and the marks.
/// The scripts run in the world of the app, so the scripts of the book do not see them.
@MainActor final class ChapterControl {
    weak var view: WKWebView?
    /// The words of a highlight that the user made from a selection, with the place of the selection.
    var onHighlight: ((String, Double) -> Void)?

    private func call(_ script: String) async -> Any? {
        guard let view else { return nil }
        return try? await view.callAsyncJavaScript(script, arguments: [:], contentWorld: .defaultClient)
    }

    private static func quoted(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }

    func sentences() async -> [String] { await call("return window.asabunko.sentences()") as? [String] ?? [] }
    func markSentence(_ index: Int) async { _ = await call("window.asabunko.markSentence(\(index)); return true") }
    func clearSentence() async { _ = await call("window.asabunko.clear('asabunko-speech'); return true") }
    /// Shows the first place of the words in the chapter. It gives false when the chapter does not have them.
    func find(_ words: String) async -> Bool { await call("return window.asabunko.find(\(Self.quoted(words)))") as? Bool ?? false }
    func showMarks(_ texts: [String]) async {
        let list = String(decoding: (try? JSONSerialization.data(withJSONObject: texts)) ?? Data("[]".utf8), as: UTF8.self)
        _ = await call("window.asabunko.marks(\(list)); return true")
    }
    /// The words that the user selected, or nil.
    func selection() async -> String? {
        let text = await call("return window.asabunko.selection()") as? String
        return text?.isEmpty == false ? text : nil
    }
    /// The first words at the top of the screen, for the title of a bookmark.
    func visibleText() async -> String { await call("return window.asabunko.visible()") as? String ?? "" }

    /// The scripts of the page. A sentence and a mark are ranges of the text of the page, and the CSS Custom
    /// Highlight API shows them with no change of the page.
    static let script = """
    (function () {
      function textNodes() {
        const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT, {
          acceptNode: (node) => node.nodeValue.trim() && !node.parentElement.closest('script, style') ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT });
        const list = [];
        while (walker.nextNode()) list.push(walker.currentNode);
        return list;
      }
      // All the text of the page in one string, with the start of each text node in it.
      function flat() {
        const nodes = textNodes(); const starts = []; let text = '';
        for (const node of nodes) { starts.push(text.length); text += node.nodeValue; }
        return { nodes, starts, text };
      }
      function locate(f, offset) {
        let low = 0, high = f.nodes.length - 1;
        while (low < high) { const mid = (low + high + 1) >> 1; if (f.starts[mid] <= offset) low = mid; else high = mid - 1; }
        return { node: f.nodes[low], offset: Math.min(offset - f.starts[low], f.nodes[low].nodeValue.length) };
      }
      function range(f, start, end) {
        const a = locate(f, start), b = locate(f, Math.max(end, start));
        const r = document.createRange(); r.setStart(a.node, a.offset); r.setEnd(b.node, b.offset); return r;
      }
      function show(r) {
        const rect = r.getBoundingClientRect();
        if (rect.top < 60 || rect.bottom > window.innerHeight - 90) window.scrollBy(0, rect.top - window.innerHeight / 3);
      }
      let sentences = null;
      window.asabunko = {
        sentences() {
          const f = flat(); const list = [];
          const pattern = /[^.!?\\u3002\\uff01\\uff1f\\u2026]+[.!?\\u3002\\uff01\\uff1f\\u2026]*["'\\u201d\\u2019\\u300d\\u300f)\\]]*\\s*/g;
          let m;
          while ((m = pattern.exec(f.text))) {
            const words = m[0].trim();
            if (words) list.push({ words, start: m.index, end: m.index + m[0].trimEnd().length });
          }
          sentences = { f, list };
          return list.map((s) => s.words);
        },
        markSentence(index) {
          if (!sentences || !sentences.list[index]) return;
          const s = sentences.list[index]; const r = range(sentences.f, s.start, s.end);
          CSS.highlights.set('asabunko-speech', new Highlight(r)); show(r);
        },
        clear(name) { CSS.highlights.delete(name); },
        find(words) {
          const f = flat(); const at = f.text.toLowerCase().indexOf(String(words).toLowerCase());
          if (at < 0) return false;
          const r = range(f, at, at + words.length); CSS.highlights.set('asabunko-find', new Highlight(r)); show(r); return true;
        },
        marks(texts) {
          const f = flat(); const h = new Highlight();
          for (const t of texts) { const at = f.text.indexOf(t); if (at >= 0) h.add(range(f, at, at + t.length)); }
          CSS.highlights.set('asabunko-marks', h);
        },
        selection() { return String(window.getSelection() || '').trim(); },
        visible() {
          for (const node of textNodes()) {
            const r = document.createRange(); r.selectNodeContents(node); const rect = r.getBoundingClientRect();
            if (rect.bottom > 60) return node.nodeValue.trim().slice(0, 80);
          }
          return '';
        },
      };
    })();
    """

    /// The colors of the sentence of the speech, of the marks, and of a result of a search.
    static let css = """
    ::highlight(asabunko-speech) { background-color: rgba(230, 170, 40, 0.35); }
    ::highlight(asabunko-marks) { background-color: rgba(255, 214, 10, 0.45); }
    ::highlight(asabunko-find) { background-color: rgba(60, 150, 255, 0.35); }
    """
}

/// A web view of a chapter with "Highlight" in the menu of a selection.
final class ChapterWebView: WKWebView {
    var onHighlight: (() -> Void)?

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        let highlight = UIAction(title: "Highlight", image: UIImage(systemName: "highlighter")) { [weak self] _ in self?.onHighlight?() }
        builder.insertChild(UIMenu(title: "", options: .displayInline, children: [highlight]), atStartOfMenu: .standardEdit)
    }
}

/// Reads the sentences of a chapter aloud, one at a time. The reader shows the sentence that it reads.
@MainActor final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var speaking = false
    @Published private(set) var index = 0
    @Published private(set) var count = 0
    private let synthesizer = AVSpeechSynthesizer()
    private var sentences: [String] = []
    private var language: String?
    var onSentence: ((Int) -> Void)?
    var onEnd: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func start(_ sentences: [String], from first: Int = 0, language: String? = nil) {
        stop()
        self.sentences = sentences
        self.language = language
        count = sentences.count
        guard sentences.indices.contains(first) else { onEnd?(); return }
        speaking = true
        speak(first)
    }

    func stop() {
        speaking = false
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func speak(_ index: Int) {
        self.index = index
        onSentence?(index)
        let utterance = AVSpeechUtterance(string: sentences[index])
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.speaking else { return }
            if self.index + 1 < self.sentences.count { self.speak(self.index + 1) } else { self.speaking = false; self.onEnd?() }
        }
    }
}
