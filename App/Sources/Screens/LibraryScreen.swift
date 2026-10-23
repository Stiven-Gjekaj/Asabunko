import AsaCore
import SwiftUI

/// The shelf: the books that the user reads now, and every book in the library.
struct LibraryScreen: View {
    @Environment(AppModel.self) private var app
    @State private var importing = false
    @State private var reading: Book?
    @State private var deleting: Book?
    @State private var updating = false

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 16, alignment: .top)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    greeting
                    if app.library.books.isEmpty {
                        emptyShelf
                    } else {
                        if !app.library.continueReading.isEmpty { continueReading }
                        allBooks
                    }
                }
                .padding(.horizontal, gutter)
                .padding(.bottom, 32)
            }
            .asaScreen()
            .toolbar {
                if app.library.books.contains(where: { $0.origin != nil }) {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            updating = true
                            Task {
                                let result = await app.refreshAll()
                                updating = false
                                app.fault = result.added == 0 && result.failed == 0 ? "No new chapters."
                                    : "\(result.added) new chapter\(result.added == 1 ? "" : "s")." + (result.failed > 0 ? " \(result.failed) books did not update." : "")
                            }
                        } label: {
                            if updating { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                        }
                        .disabled(updating)
                        .accessibilityLabel("Check for new chapters")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importing = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Import")
                }
            }
            .overlay(alignment: .bottom) { importBanner }
            .fileImporter(isPresented: $importing, allowedContentTypes: ComicTypes.all, allowsMultipleSelection: true) { result in
                guard case let .success(urls) = result else { return }
                Task { await app.importItems(urls) }
            }
            .fullScreenCover(item: $reading) { book in
                switch book.format {
                case .comic, .pdf: ReaderScreen(bookID: book.id)
                case .novel: NovelReaderScreen(bookID: book.id)
                case .series: SeriesReaderScreen(bookID: book.id)
                }
            }
            .confirmationDialog(
                "Delete \(deleting?.title ?? "")?",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let deleting { app.delete(deleting) }
                    deleting = nil
                }
            } message: {
                Text("The book and its progress leave the library. A file that you imported stays where it is.")
            }
            .alert("Asabunko", isPresented: Binding(get: { app.fault != nil }, set: { if !$0 { app.fault = nil } })) {
                Button("OK") { app.fault = nil }
            } message: {
                Text(app.fault ?? "")
            }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.greeting(at: .now))
                .font(Karla.font(15, .medium))
                .foregroundStyle(Palette.textSecondary)
            Text("Your library")
                .font(Karla.font(32, .bold, relativeTo: .largeTitle))
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// "Asa" is the morning in Japanese, so the app says hello at each time of the day.
    static func greeting(at date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        case 18..<23: "Good evening"
        default: "A quiet night for reading"
        }
    }

    private var emptyShelf: some View {
        VStack(spacing: 16) {
            Image("Mark")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                .accessibilityHidden(true)
            Text("Your shelf is empty")
                .font(Karla.font(20, .bold))
            Text("Import an EPUB, a PDF, a comic archive such as CBZ or CBR, a TXT or FB2 file, or a folder of images, from Files.")
                .font(Karla.font(15))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            Button("Import a book") { importing = true }
                .buttonStyle(PillButtonStyle())
                .padding(.top, 4)
        }
        .padding(.vertical, 36)
        .card()
    }

    private var continueReading: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Continue reading")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(app.library.continueReading) { book in
                        Button { reading = book } label: { ContinueCard(book: book, cover: app.cover(of: book)) }
                            .buttonStyle(.plain)
                            .contextMenu { menu(for: book) }
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private var allBooks: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("All books")
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(app.library.recentlyAdded) { book in
                    Button { reading = book } label: { BookTile(book: book, cover: app.cover(of: book)) }
                        .buttonStyle(.plain)
                        .contextMenu { menu(for: book) }
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Karla.font(19, .bold))
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func menu(for book: Book) -> some View {
        Button { reading = book } label: { Label("Read", systemImage: "book") }
        if book.finished || book.lastRead != nil {
            Button {
                app.update(book.id) { $0.finished = false; $0.page = 0; $0.lastRead = nil }
            } label: { Label("Mark as unread", systemImage: "arrow.uturn.backward") }
        }
        if !book.finished {
            Button {
                app.update(book.id) { $0.finished = true; $0.lastRead = .now }
            } label: { Label("Mark as read", systemImage: "checkmark") }
        }
        Button(role: .destructive) { deleting = book } label: { Label("Delete", systemImage: "trash") }
    }

    @ViewBuilder
    private var importBanner: some View {
        if let importing = app.importing {
            HStack(spacing: 10) {
                ProgressView()
                Text("Importing \(min(importing.done + 1, importing.total)) of \(importing.total)")
                    .font(Karla.font(15, .medium))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Palette.surfaceHigh, in: Capsule())
            .overlay(Capsule().stroke(Palette.outline, lineWidth: 0.5))
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// A large card for a book that the user reads now.
private struct ContinueCard: View {
    let book: Book
    let cover: URL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverView(url: cover, title: book.title).frame(width: 78)
            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(Karla.font(15, .bold))
                    .lineLimit(3)
                Text(book.format == .comic || book.format == .pdf ? "Page \(book.page + 1) of \(book.pageCount)" : "Chapter \(book.page + 1) of \(book.pageCount)")
                    .font(Karla.font(13))
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
                ProgressLine(value: book.progress)
            }
            .frame(width: 150, alignment: .leading)
        }
        .frame(height: 117)
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(Palette.outline, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

/// A cover with its title in the grid.
private struct BookTile: View {
    let book: Book
    let cover: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverView(url: cover, title: book.title)
                .overlay(alignment: .topTrailing) {
                    if book.finished {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Palette.onAccent, Palette.accent)
                            .font(.system(size: 20))
                            .padding(6)
                    }
                }
            Text(book.title)
                .font(Karla.font(14, .bold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if book.lastRead != nil && !book.finished {
                ProgressLine(value: book.progress)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(book.finished ? "Finished" : "")
    }
}
