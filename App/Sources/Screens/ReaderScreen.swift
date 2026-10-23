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

    private var count: Int { content?.count ?? 0 }

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
                    PagedReader(pages: pages, rightToLeft: mode == .rightToLeft, page: $page, onTap: tap).ignoresSafeArea()
                }
            }
            if bars { chrome.transition(.opacity) }
        }
        .statusBarHidden(!bars)
        .readerAwake()
        .persistentSystemOverlays(bars ? .automatic : .hidden)
        .asaScreen()
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
            // The left edge goes back in a western comic and forward in a manga.
            let forward = (zone == .right) != (mode == .rightToLeft)
            let next = page + (forward ? 1 : -1)
            if (0..<count).contains(next) { page = next }
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
                Text("\(page + 1) of \(count)")
                    .font(Karla.font(13, .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, gutter)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
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
