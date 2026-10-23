import AsaCore
import SwiftUI

/// Reads a novel one chapter at a time. A tap shows or hides the bars.
struct NovelReaderScreen: View {
    let bookID: Book.ID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(TextStyle.familyKey) private var family = TextStyle.Family.serif
    @AppStorage(TextStyle.sizeKey) private var size = 19.0
    @AppStorage(TextStyle.lineKey) private var lineHeight = 1.6
    @AppStorage(TextStyle.marginKey) private var margin = 22.0
    @AppStorage(TextStyle.justifyKey) private var justify = false
    @State private var novel: Novel?
    @State private var chapter = 0
    @State private var start = 0.0
    @State private var position = 0.0
    @State private var bars = true
    @State private var showChapters = false
    @State private var showStyle = false
    /// The file of the chapter that shows. A chapter of an online novel downloads first.
    @State private var file: URL?
    @State private var fault: String?

    private var book: Book? { app.book(bookID) }
    private var folder: URL? { book.map(app.folder(of:)) }
    private var style: TextStyle { TextStyle(family: family, size: size, lineHeight: lineHeight, margin: margin, justify: justify) }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            if let fault {
                VStack(spacing: 14) {
                    ContentUnavailableView("The chapter did not load", systemImage: "wifi.exclamationmark", description: Text(fault))
                    Button("Try again") { Task { await loadChapter() } }.buttonStyle(PillButtonStyle())
                }
            } else if let novel, let folder, let file, novel.chapters.indices.contains(chapter) {
                ChapterView(
                    file: file,
                    folder: folder,
                    css: style.css(dark: colorScheme == .dark),
                    start: start,
                    onPosition: { value in
                        position = value
                        app.update(bookID) { $0.read(chapter: chapter, position: value) }
                        if value >= 0.995, !bars { withAnimation { bars = true } }
                    },
                    onTap: { withAnimation(.easeOut(duration: 0.2)) { bars.toggle() } },
                    onLink: { url in open(url, in: novel, folder: folder) }
                )
                .ignoresSafeArea()
                .id(chapter)
            } else {
                ProgressView()
            }
            if bars { chrome.transition(.opacity) }
        }
        .statusBarHidden(!bars)
        .persistentSystemOverlays(bars ? .automatic : .hidden)
        .asaScreen()
        .task {
            guard let book else { return }
            novel = app.novel(of: book)
            chapter = min(book.page, max((novel?.chapters.count ?? 1) - 1, 0))
            start = book.position
            position = book.position
            await loadChapter()
        }
        .onChange(of: chapter) { Task { await loadChapter() } }
        .sheet(isPresented: $showChapters) { chapterList }
        .sheet(isPresented: $showStyle) { styleSheet.presentationDetents([.medium]) }
    }

    /// Finds the file of the chapter, and downloads it when the novel comes from a source.
    /// It also downloads the next chapter, so that it opens with no wait.
    private func loadChapter() async {
        guard let book, let novel, novel.chapters.indices.contains(chapter) else { return }
        fault = nil
        file = nil
        let index = chapter
        do {
            let url = try await app.chapterFile(of: book, index: index)
            if index == chapter { file = url }
            if novel.chapters.indices.contains(index + 1) { _ = try? await app.chapterFile(of: book, index: index + 1) }
        } catch {
            if index == chapter { fault = error.localizedDescription }
        }
    }

    private func go(to index: Int, at place: Double = 0) {
        guard let novel, novel.chapters.indices.contains(index) else { return }
        start = place
        position = place
        chapter = index
        app.update(bookID) { $0.read(chapter: index, position: place) }
    }

    private func open(_ url: URL, in novel: Novel, folder: URL) {
        let path = url.standardizedFileURL.path
        if let index = novel.chapters.firstIndex(where: { folder.appendingPathComponent($0.path).standardizedFileURL.path == path }) {
            go(to: index)
        }
    }

    private func title(of index: Int) -> String {
        novel?.chapters[index].title ?? "Chapter \(index + 1)"
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
                VStack(alignment: .leading, spacing: 1) {
                    Text(book?.title ?? "").font(Karla.font(15, .bold)).lineLimit(1)
                    if novel != nil {
                        Text(title(of: chapter)).font(Karla.font(12)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { showChapters = true } label: {
                    Image(systemName: "list.bullet").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Chapters")
                Button { showStyle = true } label: {
                    Image(systemName: "textformat.size").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Text settings")
            }
            .padding(.horizontal, 8)
            .background(.ultraThinMaterial)

            Spacer()

            HStack(spacing: 12) {
                Button { go(to: chapter - 1) } label: {
                    Label("Previous", systemImage: "chevron.left").labelStyle(.iconOnly).frame(width: 44, height: 44)
                }
                .disabled(chapter == 0)
                .accessibilityLabel("Previous chapter")
                VStack(spacing: 6) {
                    ProgressLine(value: book?.progress ?? 0)
                    Text("Chapter \(chapter + 1) of \(novel?.chapters.count ?? 0)")
                        .font(Karla.font(13, .medium))
                        .foregroundStyle(Palette.textSecondary)
                        .monospacedDigit()
                }
                Button { go(to: chapter + 1) } label: {
                    Label("Next", systemImage: "chevron.right").labelStyle(.iconOnly).frame(width: 44, height: 44)
                }
                .disabled(chapter + 1 >= (novel?.chapters.count ?? 0))
                .accessibilityLabel("Next chapter")
            }
            .font(.system(size: 17, weight: .semibold))
            .padding(.horizontal, gutter)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }

    private var chapterList: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(Array((novel?.chapters ?? []).enumerated()), id: \.offset) { index, _ in
                    Button {
                        go(to: index)
                        showChapters = false
                    } label: {
                        HStack {
                            Text(title(of: index)).font(Karla.font(16, index == chapter ? .bold : .regular))
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showChapters = false } }
            }
            .asaScreen()
        }
    }

    private var styleSheet: some View {
        NavigationStack {
            Form {
                Picker("Font", selection: $family) {
                    ForEach(TextStyle.Family.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Size") {
                    Stepper("\(Int(size))", value: $size, in: 12...34, step: 1)
                        .fixedSize()
                }
                LabeledContent("Line spacing") {
                    Stepper(String(format: "%.1f", lineHeight), value: $lineHeight, in: 1.2...2.2, step: 0.1)
                        .fixedSize()
                }
                LabeledContent("Margins") {
                    Stepper("\(Int(margin))", value: $margin, in: 8...56, step: 4)
                        .fixedSize()
                }
                Toggle("Justify the text", isOn: $justify)
            }
            .asaForm()
            .navigationTitle("Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showStyle = false } }
            }
            .asaScreen()
        }
    }
}
