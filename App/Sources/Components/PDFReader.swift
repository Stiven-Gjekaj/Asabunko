import PDFKit
import SwiftUI

/// A PDF page by page, from the left or from the right, or in one vertical column.
struct PDFReader: UIViewRepresentable {
    let document: PDFDocument
    let mode: ReadingModeKind
    @Binding var page: Int
    let onTap: () -> Void

    /// The three modes of the reader, in the words of PDFKit.
    enum ReadingModeKind: Equatable { case leftToRight, rightToLeft, vertical }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.backgroundColor = .clear
        view.autoScales = true
        view.document = document
        apply(mode, to: view)
        if let target = document.page(at: page) { view.go(to: target) }
        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.pageChanged(_:)), name: .PDFViewPageChanged, object: view
        )
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        let old = context.coordinator.parent.mode
        context.coordinator.parent = self
        if old != mode {
            let current = view.currentPage
            apply(mode, to: view)
            if let current { view.go(to: current) }
        }
        if let current = view.currentPage, document.index(for: current) != page, let target = document.page(at: page) {
            view.go(to: target)
        }
    }

    private func apply(_ mode: ReadingModeKind, to view: PDFView) {
        switch mode {
        case .vertical:
            view.usePageViewController(false)
            view.displayMode = .singlePageContinuous
            view.displayDirection = .vertical
            view.displaysRTL = false
        case .leftToRight, .rightToLeft:
            view.displayMode = .singlePage
            view.displayDirection = .horizontal
            view.displaysRTL = mode == .rightToLeft
            view.usePageViewController(true, withViewOptions: [UIPageViewController.OptionsKey.interPageSpacing: 14])
        }
        view.autoScales = true
        // PDFKit draws grey behind the pages in a column. The colour of the reader takes its place.
        view.backgroundColor = Palette.uiColor(dark: Palette.readerDark, light: Palette.readerLight)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PDFReader

        init(_ parent: PDFReader) { self.parent = parent }

        @objc func pageChanged(_ note: Notification) {
            guard let view = note.object as? PDFView, let current = view.currentPage else { return }
            let index = parent.document.index(for: current)
            if index != parent.page { parent.page = index }
        }

        @objc func tapped() { parent.onTap() }

        func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool { true }
    }
}
