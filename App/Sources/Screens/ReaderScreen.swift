import AsaCore
import PDFKit
import SwiftUI

/// What the reader of pages shows: images from the library or the network, or a PDF.
enum PageContent {
    case images([PageSource])
    case pdf(PDFDocument)

    var count: Int {
        switch self {
        case let .images(pages): pages.count
        case let .pdf(document): document.pageCount
        }
    }
}

/// Reads one comic or one PDF of the library.
struct ReaderScreen: View {
    let bookID: Book.ID
    @Environment(AppModel.self) private var app
    @State private var content: PageContent?
    @State private var page = 0

    private var book: Book? { app.book(bookID) }

    var body: some View {
        PageReader(
            title: book?.title ?? "",
            content: content,
            page: $page,
            mode: Binding(get: { book.map(app.mode(of:)) ?? .rightToLeft }, set: { mode in app.update(bookID) { $0.mode = mode } })
        )
        .task {
            guard let book else { return }
            if book.format == .pdf, let document = PDFDocument(url: app.folder(of: book).appendingPathComponent(PDFImporter.fileName)) {
                content = .pdf(document)
            } else {
                content = .images(app.pages(of: book).map(PageSource.file))
            }
            page = min(book.page, max((content?.count ?? 1) - 1, 0))
            // To open a book is to read it, so the book goes into the history and into Continue reading.
            app.update(bookID) { $0.read(page: page) }
        }
        .onChange(of: page) { _, page in
            app.update(bookID) { $0.read(page: page) }
        }
    }
}

/// Pages with the bars of the reader. A tap in the middle shows or hides the bars.
/// A tap at an edge turns the page.
struct PageReader: View {
    let title: String
    let content: PageContent?
    @Binding var page: Int
    @Binding var mode: ReadingMode
    var subtitle: String?
    @Environment(\.dismiss) private var dismiss
    @State private var bars = true
    @State private var wide = false
    @State private var stops = 0
    @AppStorage(PageLayout.fitKey) private var fit = PageFit.screen
    @AppStorage(PageLayout.cropKey) private var crop = false
    @AppStorage(PageLayout.spreadsKey) private var twoPages = true
    @AppStorage(PageLayout.shiftKey) private var shift = false
    @AppStorage(PageLayout.tapsKey) private var taps = TapZones.edges

    private var count: Int { content?.count ?? 0 }
    private var layout: PageLayout { PageLayout(fit: fit, crop: crop, spreads: twoPages, shift: shift) }

    /// The spreads of the paged reader. The vertical reader and a PDF have one page in each spread.
    private var spreads: [[Int]] {
        guard case let .images(pages) = content, mode != .vertical else { return (0..<count).map { [$0] } }
        return pageSpreads(pages, layout: layout, wide: wide)
    }

    var body: some View {
        ZStack {
            Palette.readerBackground.ignoresSafeArea()
            switch content {
            case nil:
                ProgressView()
            case let .pdf(document):
                PDFReader(document: document, mode: pdfMode, page: $page) { toggleBars() }
                    .ignoresSafeArea()
            case let .images(pages) where pages.isEmpty:
                Text("This chapter has no pages.").font(Karla.font(16)).foregroundStyle(Palette.textSecondary)
            case let .images(pages):
                switch mode {
                case .vertical:
                    VerticalReader(pages: pages, page: $page, onTap: toggleBars).ignoresSafeArea()
                case .leftToRight, .rightToLeft:
                    PagedReader(pages: pages, spreads: spreads, rightToLeft: mode == .rightToLeft, layout: layout, page: $page, onTap: tap)
                        .ignoresSafeArea()
                }
            }
            if bars { chrome.transition(.opacity) }
        }
        // Two pages show side by side when the screen is wider than it is tall.
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { wide = $0 }
        .sensoryFeedback(.impact(weight: .light), trigger: stops)
        .statusBarHidden(!bars)
        .readerAwake()
        .persistentSystemOverlays(bars ? .automatic : .hidden)
        .asaScreen()
        // A keyboard of an iPad turns the pages: the arrows go in the direction of the book, and space goes forward.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { step(mode == .rightToLeft ? 1 : -1) }
        .onKeyPress(.rightArrow) { step(mode == .rightToLeft ? -1 : 1) }
        .onKeyPress(.downArrow) { step(1) }
        .onKeyPress(.upArrow) { step(-1) }
        .onKeyPress(.space) { step(1) }
    }

    private func step(_ delta: Int) -> KeyPress.Result {
        guard count > 0 else { return .ignored }
        turn(by: delta)
        return .handled
    }

    /// Goes by one spread. A spread of two pages counts as one turn.
    private func turn(by delta: Int) {
        let spreads = spreads
        let next = Spreads.index(of: page, in: spreads) + delta
        guard spreads.indices.contains(next) else {
            // A turn past the last page stops there, with a light tap of the device.
            if delta > 0 { stops += 1 }
            return
        }
        page = representative(of: next, in: spreads)
    }

    private func toggleBars() {
        withAnimation(.easeOut(duration: 0.2)) { bars.toggle() }
    }

    private var pdfMode: PDFReader.ReadingModeKind {
        switch mode {
        case .leftToRight: .leftToRight
        case .rightToLeft: .rightToLeft
        case .vertical: .vertical
        }
    }

    private func tap(_ zone: TapZone) {
        switch zone {
        case .middle:
            toggleBars()
        case .left, .right:
            switch taps {
            case .off:
                toggleBars()
            case .forward:
                turn(by: 1)
            case .edges:
                // The left edge goes back in a western comic and forward in a manga.
                let forward = (zone == .right) != (mode == .rightToLeft)
                turn(by: forward ? 1 : -1)
            }
        }
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down").font(.system(size: 17, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("Close")
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Karla.font(16, .bold)).lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(Karla.font(12)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if mode != .vertical, case .images = content { pageMenu }
                modeMenu
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)

            Spacer()

            VStack(spacing: 8) {
                if count > 1 {
                    Slider(
                        value: Binding(get: { Double(page) }, set: { page = Int($0.rounded()) }),
                        in: 0...Double(count - 1), step: 1
                    )
                    // In a manga the first page is at the right.
                    .environment(\.layoutDirection, mode == .rightToLeft ? .rightToLeft : .leftToRight)
                    .accessibilityLabel("Page")
                    .accessibilityValue("\(page + 1) of \(count)")
                }
                Text(pageLabel)
                    .font(Karla.font(13, .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, gutter)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    /// "3 of 20", or "2-3 of 20" for a spread of two pages.
    private var pageLabel: String {
        let pages = spreads.first { $0.contains(page) } ?? [page]
        let first = (pages.first ?? page) + 1, last = (pages.last ?? page) + 1
        return first == last ? "\(first) of \(count)" : "\(first)-\(last) of \(count)"
    }

    /// The fit, the crop, the pairs of pages, and the taps of the paged reader.
    private var pageMenu: some View {
        Menu {
            Picker("Fit", selection: $fit) {
                ForEach(PageFit.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            Toggle("Crop the borders", isOn: $crop)
            Toggle("Two pages on a wide screen", isOn: $twoPages)
            if twoPages { Toggle("Move the pairs by one page", isOn: $shift) }
            Picker("Taps at the edges", selection: $taps) {
                ForEach(TapZones.allCases, id: \.self) { Text($0.name).tag($0) }
            }
        } label: {
            Image(systemName: "rectangle.split.2x1").font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
        }
        .accessibilityLabel("Page layout")
    }

    private var modeMenu: some View {
        Menu {
            Picker("Reading mode", selection: $mode) {
                ForEach(ReadingMode.allCases, id: \.self) { mode in
                    Label(mode.name, systemImage: mode.symbol).tag(mode)
                }
            }
        } label: {
            Image(systemName: mode.symbol).font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
        }
        .accessibilityLabel("Reading mode")
    }
}

extension ReadingMode {
    var name: String {
        switch self {
        case .leftToRight: "Left to right"
        case .rightToLeft: "Right to left"
        case .vertical: "Vertical scroll"
        }
    }

    var symbol: String {
        switch self {
        case .leftToRight: "arrow.right.square"
        case .rightToLeft: "arrow.left.square"
        case .vertical: "arrow.down.square"
        }
    }
}
