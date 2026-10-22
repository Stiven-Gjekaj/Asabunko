import AsaCore
import SwiftUI

/// Reads one comic. A tap in the middle shows or hides the bars. A tap at an edge turns the page.
struct ReaderScreen: View {
    let bookID: Book.ID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var pages: [URL] = []
    @State private var page = 0
    @State private var bars = true

    private var book: Book? { app.book(bookID) }
    private var mode: ReadingMode { book.map(app.mode(of:)) ?? .rightToLeft }

    var body: some View {
        ZStack {
            Palette.readerBackground.ignoresSafeArea()
            if pages.isEmpty {
                ProgressView()
            } else {
                switch mode {
                case .vertical:
                    VerticalReader(pages: pages, page: $page) { withAnimation(.easeOut(duration: 0.2)) { bars.toggle() } }
                        .ignoresSafeArea()
                case .leftToRight, .rightToLeft:
                    PagedReader(pages: pages, rightToLeft: mode == .rightToLeft, page: $page, onTap: tap)
                        .ignoresSafeArea()
                }
            }
            if bars { chrome.transition(.opacity) }
        }
        .statusBarHidden(!bars)
        .persistentSystemOverlays(bars ? .automatic : .hidden)
        .asaScreen()
        .task {
            guard let book else { return }
            pages = app.pages(of: book)
            page = min(book.page, max(pages.count - 1, 0))
        }
        .onChange(of: page) { _, page in
            app.update(bookID) { $0.read(page: page) }
        }
    }

    private func tap(_ zone: TapZone) {
        switch zone {
        case .middle:
            withAnimation(.easeOut(duration: 0.2)) { bars.toggle() }
        case .left, .right:
            // The left edge goes back in a western comic and forward in a manga.
            let forward = (zone == .right) != (mode == .rightToLeft)
            let next = page + (forward ? 1 : -1)
            if pages.indices.contains(next) { page = next }
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
                Text(book?.title ?? "")
                    .font(Karla.font(16, .bold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                modeMenu
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)

            Spacer()

            VStack(spacing: 8) {
                if pages.count > 1 {
                    Slider(
                        value: Binding(get: { Double(page) }, set: { page = Int($0.rounded()) }),
                        in: 0...Double(pages.count - 1), step: 1
                    )
                    // In a manga the first page is at the right.
                    .environment(\.layoutDirection, mode == .rightToLeft ? .rightToLeft : .leftToRight)
                    .accessibilityLabel("Page")
                    .accessibilityValue("\(page + 1) of \(pages.count)")
                }
                Text("\(page + 1) of \(pages.count)")
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
            Picker("Reading mode", selection: Binding(
                get: { mode },
                set: { mode in app.update(bookID) { $0.mode = mode } }
            )) {
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
