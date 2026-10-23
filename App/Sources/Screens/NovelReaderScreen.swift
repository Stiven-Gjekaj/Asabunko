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
    @State private var chapterQuery = ""
    @State private var showStyle = false
    /// The file of the chapter that shows. A chapter of an online novel downloads first.
    @State private var file: URL?
    @State private var fault: String?
    @StateObject private var speaker = Speaker()
    @State private var control = ChapterControl()
    /// True while the speech goes on into the next chapter.
    @State private var speakNext = false
    /// Words to show when the chapter opens, from a search or a highlight.
    @State private var pendingFind: String?
    @State private var showSearch = false
    @State private var showMarks = false
    @State private var searchWords = ""
    @State private var results: [SearchResult] = []
    @State private var missing = 0

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
            } else if let novel, novel.chapters.isEmpty {
                ContentUnavailableView("No chapters yet", systemImage: "book.closed",
                                       description: Text("The source gave no chapters for this book. Check for new chapters in the library later."))
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
                    onLink: { url in open(url, in: novel, folder: folder) },
                    control: control,
                    onReady: { Task { await ready() } }
                )
                .ignoresSafeArea()
                .id(chapter)
            } else {
                ProgressView()
            }
            if bars { chrome.transition(.opacity) }
        }
        .statusBarHidden(!bars)
        .readerAwake()
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
        .onAppear {
            speaker.onSentence = { index in Task { await control.markSentence(index) } }
            speaker.onEnd = {
                guard let novel, chapter + 1 < novel.chapters.count else { return }
                speakNext = true
                go(to: chapter + 1)
            }
            control.onHighlight = { words, place in
                app.changeLibrary { $0.marks.append(BookMark(book: bookID, chapter: chapter, position: place, text: words, kind: .highlight)) }
                Task { await showSavedMarks() }
            }
        }
        .onDisappear { speaker.stop() }
        .sheet(isPresented: $showSearch) { searchSheet }
        .sheet(isPresented: $showMarks) { marksSheet }
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

    /// The chapter shows: its marks show, a word of a search shows, and the speech goes on.
    private func ready() async {
        await showSavedMarks()
        if let words = pendingFind {
            pendingFind = nil
            _ = await control.find(words)
        }
        if speakNext {
            speakNext = false
            await startSpeech()
        }
    }

    private func showSavedMarks() async {
        let texts = app.library.marks(of: bookID).filter { $0.chapter == chapter && $0.kind == .highlight }.map(\.text)
        await control.showMarks(texts)
    }

    private func startSpeech() async {
        let sentences = await control.sentences()
        speaker.start(sentences, language: Locale.preferredLanguages.first)
    }

    private func toggleSpeech() {
        if speaker.speaking {
            speaker.stop()
            Task { await control.clearSentence() }
        } else {
            Task { await startSpeech() }
        }
    }

    private func addBookmark() {
        Task {
            let words = await control.visibleText()
            app.changeLibrary { $0.marks.append(BookMark(book: bookID, chapter: chapter, position: position, text: words.isEmpty ? title(of: chapter) : words, kind: .bookmark)) }
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
        guard let novel, novel.chapters.indices.contains(index) else { return "" }
        return novel.chapters[index].title ?? "Chapter \(index + 1)"
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
                Button { toggleSpeech() } label: {
                    Image(systemName: speaker.speaking ? "stop.circle" : "speaker.wave.2").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                }
                .accessibilityLabel(speaker.speaking ? "Stop reading aloud" : "Read aloud")
                .accessibilityValue(speaker.speaking ? "Sentence \(speaker.index + 1) of \(speaker.count)" : "")
                Button { showSearch = true } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Search the book")
                Button { showMarks = true } label: {
                    Image(systemName: "bookmark").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Marks")
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

    /// The chapters of the list, or the chapters whose title or number has the text of the search.
    private var shownChapters: [(offset: Int, element: Novel.Chapter)] {
        let all = Array((novel?.chapters ?? []).enumerated())
        let query = chapterQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter { index, item in
            String(index + 1) == query || (item.title ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private var chapterList: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(shownChapters, id: \.offset) { index, _ in
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
            .searchable(text: $chapterQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Title or number")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showChapters = false } }
            }
            .asaScreen()
        }
    }

    /// One place in the book where the words of a search are.
    struct SearchResult: Identifiable {
        let id = UUID()
        let chapter: Int
        let snippet: String
    }

    /// Searches the chapters that are on the device. The text of a chapter is its HTML with no tags.
    private func search() {
        guard let novel, let folder else { return }
        let words = searchWords.trimmingCharacters(in: .whitespaces)
        guard words.count >= 2 else { results = []; return }
        var found: [SearchResult] = []
        var absent = 0
        for (index, item) in novel.chapters.enumerated() {
            guard let html = try? String(contentsOf: folder.appendingPathComponent(item.path), encoding: .utf8) else { absent += 1; continue }
            let text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            guard let range = text.range(of: words, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
            let before = text[..<range.lowerBound].suffix(40), after = text[range.upperBound...].prefix(60)
            found.append(SearchResult(chapter: index, snippet: "…" + before + text[range] + after + "…"))
            if found.count >= 100 { break }
        }
        results = found
        missing = absent
    }

    private var searchSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(results) { result in
                        Button {
                            pendingFind = searchWords.trimmingCharacters(in: .whitespaces)
                            showSearch = false
                            if result.chapter == chapter { Task { await ready() } } else { go(to: result.chapter) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title(of: result.chapter)).font(Karla.font(15, .bold)).foregroundStyle(Palette.textPrimary)
                                Text(result.snippet).font(Karla.font(13)).foregroundStyle(Palette.textSecondary).lineLimit(2)
                            }
                        }
                    }
                } footer: {
                    if missing > 0 { Text("\(missing) chapters are not on the device, so the search does not read them.") }
                }
            }
            .asaForm()
            .searchable(text: $searchWords, placement: .navigationBarDrawer(displayMode: .always), prompt: "Words in the book")
            .onSubmit(of: .search) { search() }
            .onChange(of: searchWords) { search() }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSearch = false } } }
            .asaScreen()
        }
    }

    private var marksSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button { addBookmark() } label: { Label("Add a bookmark here", systemImage: "bookmark.fill") }
                } footer: {
                    Text("Select words in the chapter and choose Highlight to keep them.")
                }
                Section("In this book") {
                    ForEach(app.library.marks(of: bookID)) { mark in
                        Button {
                            showMarks = false
                            if mark.kind == .highlight { pendingFind = mark.text }
                            if mark.chapter == chapter && mark.kind == .highlight { Task { await ready() } } else { go(to: mark.chapter, at: mark.position) }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: mark.kind == .highlight ? "highlighter" : "bookmark.fill").foregroundStyle(Palette.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mark.text).font(Karla.font(15)).foregroundStyle(Palette.textPrimary).lineLimit(3)
                                    Text(title(of: mark.chapter)).font(Karla.font(12)).foregroundStyle(Palette.textSecondary)
                                }
                            }
                        }
                        .accessibilityLabel((mark.kind == .highlight ? "Highlight: " : "Bookmark: ") + mark.text)
                    }
                    .onDelete { offsets in
                        let ids = Set(offsets.map { app.library.marks(of: bookID)[$0].id })
                        app.changeLibrary { $0.marks.removeAll { ids.contains($0.id) } }
                        Task { await showSavedMarks() }
                    }
                }
            }
            .asaForm()
            .navigationTitle("Marks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showMarks = false } } }
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
