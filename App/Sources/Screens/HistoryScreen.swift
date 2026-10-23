import AsaCore
import SwiftUI

/// The chapters and the books that the user opened, the newest first. A tap reads the chapter again.
struct HistoryScreen: View {
    @Environment(AppModel.self) private var app
    let onRead: (Book) -> Void
    @State private var clearing = false

    var body: some View {
        List {
            ForEach(days, id: \.day) { group in
                Section(group.day.formatted(.dateTime.weekday(.wide).day().month(.wide))) {
                    ForEach(group.entries) { entry in
                        if let book = app.book(entry.book) { row(entry, book) }
                    }
                    .onDelete { offsets in
                        let ids = Set(offsets.map { group.entries[$0].id })
                        app.changeLibrary { $0.history.removeAll { ids.contains($0.id) } }
                    }
                }
            }
        }
        .asaForm()
        .asaScreen()
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") { clearing = true }.disabled(app.library.history.isEmpty)
            }
        }
        .confirmationDialog("Remove all the history?", isPresented: $clearing, titleVisibility: .visible) {
            Button("Remove all", role: .destructive) { app.changeLibrary { $0.history = [] } }
        } message: {
            Text("Your books and the place in each book stay.")
        }
        .overlay {
            if app.library.shownHistory.isEmpty {
                ContentUnavailableView("No history", systemImage: "clock", description: Text("The chapters that you open show here."))
            }
        }
    }

    private var days: [(day: Date, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        var groups: [(day: Date, entries: [HistoryEntry])] = []
        for entry in app.library.shownHistory {
            let day = calendar.startOfDay(for: entry.date)
            if groups.last?.day == day { groups[groups.count - 1].entries.append(entry) } else { groups.append((day, [entry])) }
        }
        return groups
    }

    /// The title of the chapter of an entry, from the list of the chapters of the book.
    private func chapterTitle(_ entry: HistoryEntry, _ book: Book) -> String? {
        guard book.format == .novel || book.format == .series else { return nil }
        let title = app.novel(of: book)?.chapters[safe: entry.place]?.title
        return title ?? "Chapter \(entry.place + 1)"
    }

    private func row(_ entry: HistoryEntry, _ book: Book) -> some View {
        Button {
            if book.format == .novel || book.format == .series { app.update(book.id) { $0.page = entry.place; $0.position = 0 } }
            if let opened = app.book(book.id) { onRead(opened) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title).font(Karla.font(15, .bold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                    if let chapter = chapterTitle(entry, book) {
                        Text(chapter).font(Karla.font(13)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                    }
                }
                Spacer()
                Text(entry.date.formatted(date: .omitted, time: .shortened)).font(Karla.font(13)).foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
