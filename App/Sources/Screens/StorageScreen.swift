import AsaCore
import SwiftUI

/// The space of the downloads of each online book. The user removes the downloads of a book, the chapters
/// that the user read, or all downloads.
struct StorageScreen: View {
    @Environment(AppModel.self) private var app
    @State private var sizes: [Book.ID: Int64] = [:]
    @State private var clearing = false

    var body: some View {
        List {
            Section {
                LabeledContent("Downloads", value: format(sizes.values.reduce(0, +)))
                Button("Remove all downloads", role: .destructive) { clearing = true }.disabled(sizes.isEmpty)
            } footer: {
                Text("The books from your files are not here. They stay until you delete them.")
            }
            Section("Books") {
                ForEach(books) { book in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(book.title).font(Karla.font(15, .bold)).lineLimit(1)
                            Spacer()
                            Text(format(sizes[book.id] ?? 0)).foregroundStyle(Palette.textSecondary)
                        }
                        Text("\(app.downloadedCount(book.id)) chapters on the device").font(Karla.font(13)).foregroundStyle(Palette.textSecondary)
                        HStack(spacing: 16) {
                            if book.page > 0 {
                                Button("Remove the read chapters") { app.removeDownloads(book.id, before: book.page); measure() }
                            }
                            Button("Remove all", role: .destructive) { app.downloads.cancel(book.id); app.removeDownloads(book.id); measure() }
                        }
                        .font(Karla.font(14, .bold))
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .contain)
                }
            }
        }
        .asaForm()
        .asaScreen()
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .task { measure() }
        .confirmationDialog("Remove all downloads?", isPresented: $clearing, titleVisibility: .visible) {
            Button("Remove all", role: .destructive) {
                for book in books {
                    app.downloads.cancel(book.id)
                    app.removeDownloads(book.id)
                }
                measure()
            }
        } message: {
            Text("The books stay in your library. Their chapters download again when you read them.")
        }
        .overlay {
            if sizes.isEmpty { ContentUnavailableView("No downloads", systemImage: "internaldrive", description: Text("The chapters that you download show here.")) }
        }
    }

    /// The online books with downloads, the largest first.
    private var books: [Book] {
        app.library.books.filter { sizes[$0.id] != nil }.sorted { (sizes[$0.id] ?? 0) > (sizes[$1.id] ?? 0) }
    }

    private func measure() {
        var found: [Book.ID: Int64] = [:]
        for book in app.library.books where book.origin != nil && app.downloadedCount(book.id) > 0 {
            found[book.id] = FolderSize.bytes(of: app.folder(of: book).appendingPathComponent("chapters"))
        }
        sizes = found
    }

    private func format(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}
