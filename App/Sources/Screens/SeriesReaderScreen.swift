import AsaCore
import SwiftUI

/// Reads a series of an online source, one chapter of pages at a time.
struct SeriesReaderScreen: View {
    let bookID: Book.ID
    @Environment(AppModel.self) private var app
    @State private var novel: Novel?
    @State private var chapter = 0
    @State private var content: PageContent?
    @State private var page = 0
    @State private var fault: String?
    @State private var showChapters = false
    @Environment(\.dismiss) private var dismiss

    private var book: Book? { app.book(bookID) }

    var body: some View {
        ZStack {
            if let fault {
                VStack(spacing: 14) {
                    ContentUnavailableView("The chapter did not load", systemImage: "wifi.exclamationmark", description: Text(fault))
                    Button("Try again") { Task { await load() } }.buttonStyle(PillButtonStyle())
                    Button("Close") { dismiss() }.font(Karla.font(16, .bold))
                }
                .asaScreen()
            } else {
                PageReader(
                    title: book?.title ?? "",
                    content: content,
                    page: $page,
                    mode: Binding(get: { book.map(app.mode(of:)) ?? .rightToLeft }, set: { mode in app.update(bookID) { $0.mode = mode } }),
                    subtitle: novel.flatMap { $0.chapters.indices.contains(chapter) ? $0.chapters[chapter].title : nil }
                )
                .overlay(alignment: .bottom) { chapterButtons }
            }
        }
        .task {
            guard let book else { return }
            novel = app.novel(of: book)
            chapter = min(book.page, max((novel?.chapters.count ?? 1) - 1, 0))
            await load(startAt: book.position)
        }
        .onChange(of: page) { _, page in
            let count = max(content?.count ?? 1, 1)
            app.update(bookID) { $0.read(chapter: chapter, position: count > 1 ? Double(page) / Double(count - 1) : 1) }
        }
        .sheet(isPresented: $showChapters) { chapterList }
    }

    /// The pages of the chapter, from the source.
    private func load(startAt place: Double = 0) async {
        guard let book, let novel, novel.chapters.indices.contains(chapter),
              let remote = novel.chapters[chapter].remote, let installed = app.installed(for: book), let origin = book.origin
        else {
            fault = "The source of this series is not installed."
            return
        }
        fault = nil
        content = nil
        do {
            let source = try await app.load(installed)
            let result = try await source.content(
                of: OnlineChapter(id: remote, title: novel.chapters[chapter].title ?? ""), in: OnlineSeries(id: origin.series, title: book.title)
            )
            guard case let .pages(requests) = result else { throw JSRuntimeError.badAnswer("The chapter has no pages.") }
            let pages = requests.map(PageSource.remote)
            page = min(Int((place * Double(max(pages.count - 1, 0))).rounded()), max(pages.count - 1, 0))
            content = .images(pages)
        } catch {
            fault = error.localizedDescription
        }
    }

    private func go(to index: Int) {
        guard let novel, novel.chapters.indices.contains(index) else { return }
        chapter = index
        page = 0
        app.update(bookID) { $0.read(chapter: index, position: 0) }
        Task { await load() }
    }

    /// The buttons for the previous chapter, the list, and the next chapter. They show on the last page.
    @ViewBuilder
    private var chapterButtons: some View {
        if let count = content?.count, page >= count - 1, let novel {
            HStack(spacing: 10) {
                if chapter > 0 {
                    Button("Previous chapter") { go(to: chapter - 1) }.buttonStyle(PillButtonStyle())
                }
                Button { showChapters = true } label: { Image(systemName: "list.bullet") }
                    .buttonStyle(PillButtonStyle())
                    .accessibilityLabel("Chapters")
                if chapter + 1 < novel.chapters.count {
                    Button("Next chapter") { go(to: chapter + 1) }.buttonStyle(PillButtonStyle())
                }
            }
            .padding(.bottom, 96)
        }
    }

    private var chapterList: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(Array((novel?.chapters ?? []).enumerated()), id: \.offset) { index, item in
                    Button {
                        go(to: index)
                        showChapters = false
                    } label: {
                        HStack {
                            Text(item.title ?? "Chapter \(index + 1)").font(Karla.font(16, index == chapter ? .bold : .regular))
                            Spacer()
                            if index == chapter { Image(systemName: "bookmark.fill").foregroundStyle(Palette.accent) }
                        }
                    }
                    .listRowBackground(Palette.surface)
                    .id(index)
                }
                .asaForm()
                .onAppear { proxy.scrollTo(chapter, anchor: .center) }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showChapters = false } } }
            .asaScreen()
        }
    }
}
