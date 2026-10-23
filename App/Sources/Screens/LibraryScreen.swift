import AsaCore
import SwiftUI

/// The shelf: the books that the user reads now, and the read list.
struct LibraryScreen: View {
    @Environment(AppModel.self) private var app
    @State private var importing = false
    @State private var reading: Book?
    @State private var deleting: Book?
    @State private var updating = false
    @AppStorage("library.order") private var order = ReadListOrder.added
    @State private var query = ""
    @State private var filters: Set<LibraryFilter> = []
    @State private var category: UUID?
    @State private var editingCategories = false
    @State private var tracking: Book?

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 16, alignment: .top)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    greeting
                    if query.isEmpty {
                        if !app.library.shownUpdates.isEmpty { updatesLink }
                        if !app.library.shownHistory.isEmpty { historyLink }
                    }
                    if app.library.continueReading.isEmpty && app.library.readList.isEmpty {
                        emptyShelf
                    } else {
                        if !app.library.continueReading.isEmpty && query.isEmpty && filters.isEmpty { continueReading }
                        if app.library.readList.isEmpty {
                            EmptyArt(covers: [], title: "Your read list is empty",
                                     text: "Tap the bookmark on the page of a title to keep it here. A book that you import goes here too.")
                        } else {
                            readList
                        }
                    }
                }
                .padding(.horizontal, gutter)
                .padding(.bottom, 32)
            }
            .asaScreen()
            .searchable(text: $query, prompt: "Search the library")
            .sheet(isPresented: $editingCategories) { CategoriesSheet() }
            .sheet(item: $tracking) { book in TrackSheet(bookID: book.id) }
            .refreshable {
                guard app.library.books.contains(where: { $0.origin != nil }) else { return }
                let result = await app.refreshAll()
                if result.added > 0 || result.failed > 0 {
                    app.fault = "\(result.added) new chapter\(result.added == 1 ? "" : "s")." + (result.failed > 0 ? " \(result.failed) books did not update." : "")
                }
            }
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
            // A notification of new chapters opens its book.
            .onChange(of: app.openRequest, initial: true) { _, id in
                guard let id, let book = app.book(id) else { return }
                app.openRequest = nil
                reading = book
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
        }
    }

    /// The chapters that the user opened, the newest first.
    private var historyLink: some View {
        NavigationLink {
            HistoryScreen { book in reading = book }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 20)).foregroundStyle(Palette.accent)
                Text("History").font(Karla.font(16, .bold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Palette.textSecondary)
            }
            .padding(14)
            .card()
        }
        .accessibilityElement(children: .combine)
    }

    /// The new chapters of the checks, in one list.
    private var updatesLink: some View {
        NavigationLink {
            UpdatesScreen { book in reading = book }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack").font(.system(size: 20)).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Updates").font(Karla.font(16, .bold)).foregroundStyle(Palette.textPrimary)
                    let count = app.library.shownUpdates.count
                    Text(count == 1 ? "1 new chapter" : "\(count) new chapters").font(Karla.font(13)).foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Palette.textSecondary)
            }
            .padding(14)
            .card()
        }
        .accessibilityElement(children: .combine)
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
        EmptyArt(
            covers: app.discover.covers.dropFirst(3).map { $0 },
            title: "Your shelf is empty",
            text: "Find a title in Discover or Search, and bookmark it. Or import an EPUB, a PDF, a comic archive such as CBZ or CBR, a TXT, FB2, MOBI, or AZW3 file, or a folder of images, from Files."
        ) {
            Button("Import a book") { importing = true }.buttonStyle(PillButtonStyle())
        }
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

    private var readList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Read list")
                Spacer()
                Menu {
                    ForEach(LibraryFilter.allCases, id: \.self) { filter in
                        Toggle(filter.name, isOn: Binding(get: { filters.contains(filter) }, set: { on in
                            if on { filters.insert(filter) } else { filters.remove(filter) }
                        }))
                    }
                } label: {
                    Image(systemName: filters.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 20))
                }
                .accessibilityLabel("Filter the read list")
                .accessibilityValue(filters.isEmpty ? "Off" : filters.map(\.name).sorted().joined(separator: ", "))
                Menu {
                    Picker("Order", selection: $order) {
                        ForEach(ReadListOrder.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                } label: {
                    Label(order.name, systemImage: "arrow.up.arrow.down").font(Karla.font(14, .bold))
                }
                .accessibilityLabel("Order of the read list")
                .accessibilityValue(order.name)
            }
            categoryChips
            let shown = visibleBooks
            if shown.isEmpty {
                Text(query.isEmpty ? "No book of the read list fits the filters." : "No book of the read list has \"\(query)\" in its title.")
                    .font(Karla.font(14)).foregroundStyle(Palette.textSecondary)
            }
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(shown) { book in
                    Button { reading = book } label: { BookTile(book: book, cover: app.cover(of: book)) }
                        .buttonStyle(.plain)
                        .contextMenu { menu(for: book) }
                }
            }
        }
    }

    /// The books of the read list in the category, with the search and the filters.
    private var visibleBooks: [Book] {
        let words = query.trimmingCharacters(in: .whitespaces)
        return app.library.readList(in: category, by: order).filter { book in
            (words.isEmpty || book.title.localizedStandardContains(words) || (book.author ?? "").localizedStandardContains(words))
                && filters.allSatisfy { $0.keeps(book, app: app) }
        }
    }

    /// "All", then one chip for each category, then a chip that edits the categories.
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: category == nil) { category = nil }
                ForEach(app.library.categories) { item in
                    chip(item.name, selected: category == item.id) { category = item.id }
                }
                Button { editingCategories = true } label: {
                    Label(app.library.categories.isEmpty ? "Add a category" : "Edit", systemImage: app.library.categories.isEmpty ? "plus" : "pencil")
                        .font(Karla.font(14, .bold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(Palette.surfaceHigh, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.library.categories.isEmpty ? "Add a category" : "Edit the categories")
            }
        }
        .scrollClipDisabled()
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(Karla.font(14, .bold))
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .foregroundStyle(selected ? Palette.onAccent : Palette.textPrimary)
            .background(selected ? Palette.accent : Palette.surfaceHigh, in: Capsule())
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
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
        if book.origin != nil {
            Button { app.downloadChapters(book.id) } label: { Label("Download all chapters", systemImage: "arrow.down.circle") }
            if app.downloadedCount(book.id) > 0 {
                Button { app.downloads.cancel(book.id); app.removeDownloads(book.id) } label: { Label("Remove downloads", systemImage: "xmark.bin") }
            }
        }
        if book.listed && !app.library.categories.isEmpty {
            Menu {
                ForEach(app.library.categories) { item in
                    Toggle(item.name, isOn: Binding(get: { app.book(book.id)?.categories.contains(item.id) ?? false }, set: { on in
                        app.update(book.id) { $0.categories.removeAll { $0 == item.id }; if on { $0.categories.append(item.id) } }
                    }))
                }
            } label: { Label("Categories", systemImage: "tag") }
        }
        Button { tracking = book } label: { Label("Track", systemImage: "chart.line.uptrend.xyaxis") }
        if book.listed && book.origin != nil {
            Button { app.update(book.id) { $0.listed = false } } label: { Label("Remove from the read list", systemImage: "bookmark.slash") }
        } else if !book.listed {
            Button { app.update(book.id) { $0.listed = true } } label: { Label("Add to the read list", systemImage: "bookmark") }
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
            // The file name of an online book is the name of its source.
            if book.origin != nil {
                Text(book.fileName).font(Karla.font(12)).foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
            if book.lastRead != nil && !book.finished {
                ProgressLine(value: book.progress)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(book.finished ? "Finished" : "")
    }
}

/// A filter of the read list.
enum LibraryFilter: String, CaseIterable, Hashable {
    case unread, downloaded, comics, novels

    var name: String {
        switch self {
        case .unread: "Unread"
        case .downloaded: "On the device"
        case .comics: "Comics"
        case .novels: "Novels"
        }
    }

    @MainActor func keeps(_ book: Book, app: AppModel) -> Bool {
        switch self {
        case .unread: !book.finished
        // A book from a file is on the device. An online book needs a downloaded chapter.
        case .downloaded: book.origin == nil || app.downloadedCount(book.id) > 0
        case .comics: book.format != .novel
        case .novels: book.format == .novel
        }
    }
}

/// Adds, renames, orders, and removes the categories of the read list.
struct CategoriesSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New category", text: $name).onSubmit(add)
                        Button("Add", action: add).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section {
                    ForEach(app.library.categories) { item in
                        TextField("Name", text: Binding(get: { item.name }, set: { new in
                            app.changeLibrary { library in
                                if let index = library.categories.firstIndex(where: { $0.id == item.id }) { library.categories[index].name = new }
                            }
                        }))
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { app.library.categories[$0].id }
                        app.changeLibrary { library in ids.forEach { library.removeCategory($0) } }
                    }
                    .onMove { from, to in app.changeLibrary { $0.categories.move(fromOffsets: from, toOffset: to) } }
                } footer: {
                    if !app.library.categories.isEmpty {
                        Text("Hold a book of the read list to put it in a category. Swipe a category to remove it. A book stays in the read list when its category goes.")
                    }
                }
            }
            .asaForm()
            .asaScreen()
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func add() {
        let text = name.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        app.changeLibrary { $0.categories.append(BookCategory(name: text)) }
        name = ""
    }
}
