import AsaCore
import SwiftUI

/// The new chapters that the checks found, the newest first. A tap reads the chapter.
struct UpdatesScreen: View {
    @Environment(AppModel.self) private var app
    let onRead: (Book) -> Void

    var body: some View {
        List {
            ForEach(days, id: \.day) { group in
                Section(group.day.formatted(.dateTime.weekday(.wide).day().month(.wide))) {
                    ForEach(group.updates) { update in
                        if let book = app.book(update.book) { row(update, book) }
                    }
                }
            }
        }
        .asaForm()
        .asaScreen()
        .navigationTitle("Updates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") { app.changeLibrary { $0.updates = [] } }
            }
        }
        .overlay {
            if app.library.shownUpdates.isEmpty {
                ContentUnavailableView("No updates", systemImage: "sparkles", description: Text("New chapters of your books show here after a check."))
            }
        }
    }

    /// The updates by the day of the check.
    private var days: [(day: Date, updates: [ChapterUpdate])] {
        let calendar = Calendar.current
        var groups: [(day: Date, updates: [ChapterUpdate])] = []
        for update in app.library.shownUpdates {
            let day = calendar.startOfDay(for: update.found)
            if groups.last?.day == day { groups[groups.count - 1].updates.append(update) } else { groups.append((day, [update])) }
        }
        return groups
    }

    private func row(_ update: ChapterUpdate, _ book: Book) -> some View {
        Button {
            // The reader opens at the new chapter.
            app.update(book.id) { $0.page = update.chapter; $0.position = 0 }
            if let opened = app.book(book.id) { onRead(opened) }
        } label: {
            HStack(spacing: 12) {
                RemoteCoverThumb(url: app.cover(of: book))
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title).font(Karla.font(15, .bold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                    Text(update.title ?? "Chapter \(update.chapter + 1)").font(Karla.font(13)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
                Spacer()
                if app.isDownloaded(book.id, index: update.chapter) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent).accessibilityLabel("Downloaded")
                }
            }
        }
    }
}

/// A small cover of a book in a list.
private struct RemoteCoverThumb: View {
    let url: URL
    var body: some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Palette.surfaceHigh }
            .frame(width: 40, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }
}
