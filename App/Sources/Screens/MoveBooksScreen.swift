import AsaCore
import SwiftUI

/// Moves many online books to another source at one time, such as when a source stops working.
/// The app finds the best title in the new source for each book, and the user sees the matches before the move.
struct MoveBooksScreen: View {
    @Environment(AppModel.self) private var app
    @State private var chosen: Set<Book.ID> = []
    @State private var target: InstalledSource.ID?
    @State private var matches: [Book.ID: Match] = [:]
    @State private var finding = false
    @State private var moved: Int?

    struct Match {
        var details: OnlineDetails?
        var use: Bool
    }

    var body: some View {
        Form {
            Section {
                ForEach(books) { book in
                    Button {
                        if chosen.contains(book.id) { chosen.remove(book.id) } else { chosen.insert(book.id) }
                        matches = [:]
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(book.title).foregroundStyle(Palette.textPrimary).lineLimit(1)
                                Text(book.fileName).font(Karla.font(13)).foregroundStyle(Palette.textSecondary)
                            }
                            Spacer()
                            if chosen.contains(book.id) { Image(systemName: "checkmark").foregroundStyle(Palette.accent).accessibilityLabel("Selected") }
                        }
                    }
                }
            } header: {
                Text("Books")
            } footer: {
                Text("Choose the books to move.")
            }
            Section("To") {
                Picker("Source", selection: $target) {
                    Text("Choose a source").tag(InstalledSource.ID?.none)
                    ForEach(app.library.installed) { installed in Text(installed.info.name).tag(Optional(installed.id)) }
                }
                .onChange(of: target) { matches = [:] }
                Button("Find the titles") { Task { await find() } }
                    .disabled(chosen.isEmpty || target == nil || finding)
            }
            if finding { Section { ProgressView("Searching") } }
            if !matches.isEmpty {
                Section {
                    ForEach(books.filter { chosen.contains($0.id) }) { book in
                        matchRow(book)
                    }
                    Button("Move \(usable.count) book\(usable.count == 1 ? "" : "s")") { move() }
                        .disabled(usable.isEmpty)
                } header: {
                    Text("Matches")
                } footer: {
                    Text("Each book keeps its place at the chapter with the same number. The downloads of the old source leave the device.")
                }
            }
            if let moved { Section { Text("\(moved) book\(moved == 1 ? "" : "s") moved.") } }
        }
        .asaForm()
        .asaScreen()
        .navigationTitle("Move books")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The online books of the library, the read list first.
    private var books: [Book] {
        app.library.books.filter { $0.origin != nil }.sorted { ($0.listed ? 0 : 1, $0.title) < ($1.listed ? 0 : 1, $1.title) }
    }

    private var installed: InstalledSource? { app.library.installed.first { $0.id == target } }

    private var usable: [(Book, OnlineDetails)] {
        books.compactMap { book in
            guard let match = matches[book.id], match.use, let details = match.details else { return nil }
            return (book, details)
        }
    }

    private func matchRow(_ book: Book) -> some View {
        let match = matches[book.id]
        return Toggle(isOn: Binding(get: { match?.use ?? false }, set: { matches[book.id]?.use = $0 })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title).lineLimit(1)
                if let details = match?.details {
                    Text("\(details.series.title) · \(details.chapters.count) chapters").font(Karla.font(13)).foregroundStyle(Palette.textSecondary)
                } else {
                    Text("Not found in this source").font(Karla.font(13)).foregroundStyle(Palette.danger)
                }
            }
        }
        .disabled(match?.details == nil)
    }

    /// Searches the new source for each book. A title must start with the title of the book, or be the same.
    private func find() async {
        guard let installed else { return }
        finding = true
        defer { finding = false }
        moved = nil
        guard let source = try? await app.load(installed) else {
            app.fault = "\(installed.info.name) did not load."
            return
        }
        var found: [Book.ID: Match] = [:]
        for book in books where chosen.contains(book.id) {
            let page = try? await source.search(book.title, page: 1)
            let best = (page?.items ?? []).map { ($0, TitleMatch.score($0.title, query: book.title)) }.filter { $0.1 >= 2 }.max { $0.1 < $1.1 }?.0
            let details = if let best { try? await source.details(of: best) } else { OnlineDetails?.none }
            found[book.id] = Match(details: details, use: details != nil)
        }
        matches = found
    }

    private func move() {
        guard let installed else { return }
        var count = 0
        for (book, details) in usable {
            do {
                try app.move(book, to: installed, details: details)
                count += 1
            } catch {
                app.fault = "\(book.title) did not move: \(error.localizedDescription)"
            }
        }
        moved = count
        matches = [:]
        chosen = []
    }
}
