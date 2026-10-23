import AsaCore
import SwiftUI

/// The sources of one list, such as the LNReader plugins, with a button to install each one.
struct SourceListScreen: View {
    let link: SourceLink
    @Environment(AppModel.self) private var app
    @State private var sources: [SourceInfo]?
    @State private var fault: String?
    @State private var filter = ""
    @State private var working: Set<String> = []
    @AppStorage("browse.adult") private var adult = false

    private var shown: [SourceInfo] {
        (sources ?? []).filter { (adult || !$0.adult) && (filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) || $0.language.localizedCaseInsensitiveContains(filter)) }
    }

    private var languages: [String] {
        Array(Set(shown.map(\.language))).sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    var body: some View {
        List {
            if let fault {
                ContentUnavailableView("The list did not load", systemImage: "wifi.exclamationmark", description: Text(fault))
            } else if sources == nil {
                ProgressView().frame(maxWidth: .infinity)
            }
            ForEach(languages, id: \.self) { language in
                Section(language.isEmpty ? "Other" : language) {
                    ForEach(shown.filter { $0.language == language }) { info in row(info) }
                }
            }
        }
        .asaForm()
        .asaScreen()
        .navigationTitle(link.name ?? link.kind?.name ?? "Sources")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $filter, prompt: "Name or language")
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: BrowserChecks.shared.passes) { Task { await load() } }
    }

    private func row(_ info: SourceInfo) -> some View {
        HStack(spacing: 12) {
            SourceIcon(url: info.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.name).font(Karla.font(16, .bold))
                Text([info.version.isEmpty ? nil : "Version \(info.version)", info.adult ? "18+" : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(Karla.font(12)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            if working.contains(info.id) {
                ProgressView()
            } else if app.isInstalled(info, from: link) {
                Button(link.kind == .suwayomi ? "Hide" : "Remove") {
                    if let installed = app.library.installed.first(where: { $0.list == link.id && $0.info.id == info.id }) { app.uninstall(installed) }
                }
                .font(Karla.font(14, .bold))
                .foregroundStyle(Palette.danger)
                .buttonStyle(.borderless)
            } else {
                Button(link.kind == .suwayomi ? "Show" : "Install") {
                    working.insert(info.id)
                    Task {
                        do { try await app.install(info, from: link) } catch { app.fault = "\(info.name) did not install: \(error.localizedDescription)" }
                        working.remove(info.id)
                    }
                }
                .font(Karla.font(14, .bold))
                .buttonStyle(.borderless)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        do {
            sources = try await app.sources(in: link)
            fault = nil
        } catch {
            fault = error.localizedDescription
        }
    }
}

/// The small icon of a source.
struct SourceIcon: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Palette.surfaceHigh)
            .frame(width: 36, height: 36)
            .overlay { if let image { Image(uiImage: image).resizable().scaledToFill() } }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .task(id: url) {
                guard let url else { return }
                image = await PageImages.shared.image(.remote(URLRequest(url: url)), maxPixels: 108)
            }
            .accessibilityHidden(true)
    }
}

/// One installed source: its popular and latest lists, and its search.
struct OnlineSourceScreen: View {
    let installed: InstalledSource
    @Environment(AppModel.self) private var app
    @State private var source: OnlineSource?
    @State private var list = Listing.popular
    @State private var items: [OnlineSeries] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var loading = false
    @State private var fault: String?
    @State private var query = ""
    @State private var searching = ""
    @State private var filters: [SourceOption] = []
    /// The values of the filters that the user applied. Empty means the list of the source with no filters.
    @State private var applied: [String: OptionValue] = [:]
    @State private var showFilters = false
    @State private var hasSettings = false

    enum Listing: String, CaseIterable { case popular = "Popular", latest = "Latest" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if searching.isEmpty, applied.isEmpty, source?.canShowLatest == true {
                    Picker("List", selection: $list) {
                        ForEach(Listing.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if let fault {
                    ContentUnavailableView("The source did not answer", systemImage: "wifi.exclamationmark", description: Text(fault))
                } else if items.isEmpty && !loading {
                    ContentUnavailableView("Nothing here", systemImage: "tray", description: Text(searching.isEmpty ? "The source gave no books." : "No results for \"\(searching)\"."))
                }
                if let source {
                    CoverGrid(
                        items: items, title: \.title, subtitle: { _ in nil },
                        cover: { $0.cover.map(source.imageRequest) },
                        destination: { OnlineSeriesScreen(installed: installed, series: $0) }
                    )
                }
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if hasMore {
                    Button("Load more") { Task { await loadPage(page + 1) } }
                        .buttonStyle(PillButtonStyle())
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, gutter)
            .padding(.bottom, 32)
        }
        .asaScreen()
        .navigationTitle(installed.info.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        .onSubmit(of: .search) { searching = query; Task { await loadPage(1) } }
        .onChange(of: query) { _, text in if text.isEmpty && !searching.isEmpty { searching = ""; Task { await loadPage(1) } } }
        .onChange(of: list) { Task { await loadPage(1) } }
        .onChange(of: BrowserChecks.shared.passes) { if fault != nil { Task { await loadPage(1) } } }
        .toolbar {
            if !filters.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilters = true } label: {
                        Image(systemName: applied.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filters")
                    .accessibilityValue(applied.isEmpty ? "Off" : "On")
                }
            }
            if hasSettings, let source {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SourceSettingsScreen(source: source, name: installed.info.name) } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Source settings")
                }
            }
        }
        .sheet(isPresented: $showFilters) {
            FilterSheet(options: filters, applied: applied) { values in
                applied = values
                Task { await loadPage(1) }
            }
        }
        .task {
            guard source == nil else { return }
            do {
                let loaded = try await app.load(installed)
                source = loaded
                filters = await loaded.filterOptions()
                hasSettings = !(await loaded.settingOptions()).isEmpty
                await loadPage(1)
            } catch {
                fault = error.localizedDescription
            }
        }
    }

    private func loadPage(_ number: Int) async {
        guard let source else { return }
        loading = true
        defer { loading = false }
        if number == 1 { items = [] }
        do {
            let result: OnlinePage
            if !applied.isEmpty {
                result = try await source.browse(page: number, query: searching, filters: applied)
            } else if !searching.isEmpty {
                result = try await source.search(searching, page: number)
            } else if list == .latest {
                result = try await source.latest(page: number)
            } else {
                result = try await source.popular(page: number)
            }
            let known = Set(items.map(\.id))
            items += result.items.filter { !known.contains($0.id) }
            hasMore = result.hasMore && !result.items.allSatisfy { known.contains($0.id) }
            page = number
            fault = nil
        } catch {
            fault = error.localizedDescription
        }
    }
}

/// A series or a novel: its facts, its chapters, and a button to add it to the read list.
/// The title can be in many sources. The page asks each one and shows the source with the most chapters.
/// The user can choose another source in the Source menu.
struct OnlineSeriesScreen: View {
    @Environment(AppModel.self) private var app
    @State private var hits: [SearchHit]
    /// True when the page looks for the same title in the other sources.
    private let findOthers: Bool
    @State private var chosen: SearchHit
    /// True after the user chooses a source. Then a late answer does not change the source.
    @State private var userChose = false
    @State private var answers: [String: OnlineDetails] = [:]
    @State private var faults: [String: String] = [:]
    @State private var comparing = false
    @State private var adding = false
    @State private var reading: Book?
    @State private var newestFirst = false
    @AppStorage("series.byVolume") private var byVolume = false
    /// The range of chapters that the list shows, such as 1-50, when the series has many chapters.
    @State private var range: Int?

    /// One series of one source. The page also looks for the title in the other sources.
    init(installed: InstalledSource, series: OnlineSeries) {
        let hit = SearchHit(source: installed.id, series: series)
        _hits = State(initialValue: [hit])
        _chosen = State(initialValue: hit)
        findOthers = true
    }

    /// The same title in some sources, from a search.
    init(hits: [SearchHit]) {
        _hits = State(initialValue: hits)
        _chosen = State(initialValue: hits[0])
        findOthers = false
    }

    private var installed: InstalledSource? { app.library.installed.first { $0.id == chosen.source } }
    private var series: OnlineSeries { chosen.series }
    private var details: OnlineDetails? { answers[chosen.source] }
    private var fault: String? { faults[chosen.source] }
    @State private var source: OnlineSource?

    private var book: Book? {
        guard let installed else { return nil }
        return app.library.book(from: BookOrigin(list: installed.list, source: installed.info.id, series: series.id))
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    RemoteCover(request: (details?.series.cover ?? series.cover).flatMap { url in source?.imageRequest(url) }, title: series.title)
                        .frame(width: 110)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(details?.series.title ?? series.title).font(Karla.font(20, .bold))
                        if let author = details?.author { Text(author).font(Karla.font(15)).foregroundStyle(Palette.textSecondary) }
                        if let status = details?.status { Text(status).font(Karla.font(13)).foregroundStyle(Palette.textSecondary) }
                        sourceMenu
                    }
                }
                .listRowBackground(Color.clear)
                if let details {
                    HStack(spacing: 10) {
                        Button(book?.lastRead == nil ? "Start reading" : "Continue") {
                            Task {
                                if let book { reading = book } else { await open(chapter: 0, details: details) }
                            }
                        }
                        .buttonStyle(PillButtonStyle())
                        .disabled(details.chapters.isEmpty)
                        Button {
                            Task { await toggleList(details) }
                        } label: {
                            Image(systemName: book?.listed == true ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 22)).frame(width: 44, height: 44)
                        }
                        .disabled(adding)
                        .accessibilityLabel(book?.listed == true ? "Remove from the read list" : "Add to the read list")
                        if let book {
                            Menu {
                                Button { app.downloadChapters(book.id) } label: { Label("Download all chapters", systemImage: "arrow.down.circle") }
                                Button { app.downloadChapters(book.id, from: book.page) } label: { Label("Download from this chapter", systemImage: "arrow.down.to.line") }
                                Button(role: .destructive) { app.downloads.cancel(book.id); app.removeDownloads(book.id) } label: { Label("Remove downloads", systemImage: "trash") }
                            } label: {
                                Image(systemName: "arrow.down.circle").font(.system(size: 22)).frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Downloads")
                        }
                    }
                    .buttonStyle(.borderless)
                    .listRowBackground(Color.clear)
                    if let summary = details.summary {
                        Text(summary).font(Karla.font(15)).listRowBackground(Color.clear)
                    }
                    if !details.genres.isEmpty {
                        Text(details.genres.joined(separator: " · ")).font(Karla.font(13)).foregroundStyle(Palette.textSecondary).listRowBackground(Color.clear)
                    }
                }
            }
            if let fault {
                ContentUnavailableView("The source did not answer", systemImage: "wifi.exclamationmark", description: Text(fault))
            } else if let details {
                chapterList(details)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    if hits.count > 1 { Text("Comparing \(hits.count) sources").font(Karla.font(13)).foregroundStyle(Palette.textSecondary) }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        }
        .asaForm()
        .asaScreen()
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: BrowserChecks.shared.passes) { Task { await load() } }
        .task(id: chosen) { await prepare() }
        .fullScreenCover(item: $reading) { book in
            switch book.format {
            case .novel: NovelReaderScreen(bookID: book.id)
            default: SeriesReaderScreen(bookID: book.id)
            }
        }
    }

    /// The chapters, by volume or in ranges of 50, so that a long series needs little scrolling.
    @ViewBuilder
    private func chapterList(_ details: OnlineDetails) -> some View {
        let titles = details.chapters.map(\.title)
        let volumes = ChapterGroups.volumes(titles)
        let ranges = ChapterGroups.ranges(count: titles.count)
        let shownVolumes = byVolume ? volumes : nil
        Section {
            if volumes != nil {
                Picker("Show", selection: $byVolume) {
                    Text("Chapters").tag(false)
                    Text("Volumes").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            if shownVolumes == nil && ranges.count > 1 {
                rangeChips(ranges)
            }
        } header: {
            HStack {
                Text(details.chapters.count == 1 ? "1 chapter" : "\(details.chapters.count) chapters")
                Spacer()
                Button(newestFirst ? "Oldest first" : "Newest first") { newestFirst.toggle() }.font(Karla.font(13, .bold))
            }
        }
        if let shownVolumes {
            ForEach(newestFirst ? shownVolumes.reversed() : shownVolumes) { volume in
                Section {
                    DisclosureGroup {
                        ForEach(newestFirst ? volume.chapters.reversed() : volume.chapters, id: \.self) { index in
                            chapterRow(index, details)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(volume.name).font(Karla.font(16, .bold))
                                Text(volume.chapters.count == 1 ? "1 chapter" : "\(volume.chapters.count) chapters")
                                    .font(Karla.font(12)).foregroundStyle(Palette.textSecondary)
                            }
                            Spacer()
                            Button("Read") { Task { await open(chapter: start(of: volume), details: details) } }
                                .font(Karla.font(14, .bold))
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Read \(volume.name)")
                        }
                    }
                    .listRowBackground(Palette.surface)
                }
            }
        } else {
            let shown = ranges.isEmpty ? 0..<0 : ranges[min(range ?? defaultRange(ranges), ranges.count - 1)]
            Section {
                ForEach(newestFirst ? Array(shown.reversed()) : Array(shown), id: \.self) { index in
                    chapterRow(index, details).listRowBackground(Palette.surface)
                }
            }
        }
    }

    /// The chips of the ranges, such as 1-50 and 51-100.
    private func rangeChips(_ ranges: [Range<Int>]) -> some View {
        let selected = min(range ?? defaultRange(ranges), ranges.count - 1)
        let order = newestFirst ? Array(ranges.indices.reversed()) : Array(ranges.indices)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(order, id: \.self) { index in
                    Button(ChapterGroups.name(of: ranges[index])) { range = index }
                        .font(Karla.font(14, .bold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .foregroundStyle(index == selected ? Palette.onAccent : Palette.textPrimary)
                        .background(index == selected ? Palette.accent : Palette.surfaceHigh, in: Capsule())
                        .buttonStyle(.plain)
                        .accessibilityLabel("Chapters \(ChapterGroups.name(of: ranges[index]))")
                        .accessibilityAddTraits(index == selected ? .isSelected : [])
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    /// The range of the chapter that the user reads, or the first range.
    private func defaultRange(_ ranges: [Range<Int>]) -> Int {
        guard let book, book.lastRead != nil else { return newestFirst ? ranges.count - 1 : 0 }
        return ranges.firstIndex { $0.contains(book.page) } ?? 0
    }

    /// The first chapter of a volume that the user did not read, or its first chapter.
    private func start(of volume: ChapterGroups.Volume) -> Int {
        guard let book, book.lastRead != nil else { return volume.chapters[0] }
        return volume.chapters.first { $0 >= book.page } ?? volume.chapters[0]
    }

    private func chapterRow(_ index: Int, _ details: OnlineDetails) -> some View {
        let chapter = details.chapters[index]
        return Button { Task { await open(chapter: index, details: details) } } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.title).font(Karla.font(15, isCurrent(index) ? .bold : .regular))
                    if let date = chapter.date { Text(date).font(Karla.font(12)).foregroundStyle(Palette.textSecondary) }
                }
                Spacer()
                if isCurrent(index) { Image(systemName: "bookmark.fill").foregroundStyle(Palette.accent) }
                downloadMark(index)
            }
        }
    }

    /// The source of the page, and a list of each source that has the title, with its number of chapters.
    private var sourceMenu: some View {
        Menu {
            ForEach(hits, id: \.self) { hit in
                Button {
                    chosen = hit
                    userChose = true
                } label: {
                    if hit == chosen {
                        Label(line(hit), systemImage: "checkmark")
                    } else {
                        Text(line(hit))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(installed?.info.name ?? "Source").font(Karla.font(13, .bold))
                if hits.count > 1 {
                    Text("· \(hits.count) sources").font(Karla.font(13))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(Palette.accent)
            .frame(minHeight: 32)
        }
        .disabled(hits.count < 2)
        .accessibilityLabel("Source")
        .accessibilityValue(installed?.info.name ?? "")
    }

    /// "Name · 12 chapters", or why the source has no number.
    private func line(_ hit: SearchHit) -> String {
        let name = app.library.installed.first { $0.id == hit.source }?.info.name ?? "Source"
        if let details = answers[hit.source] {
            let count = SourceChoice.distinctChapters(details.chapters)
            return "\(name) · \(count == 1 ? "1 chapter" : "\(count) chapters")"
        }
        if faults[hit.source] != nil { return "\(name) · no answer" }
        return "\(name) · loading"
    }

    /// The state of the download of a chapter: on the device, downloading, or waiting.
    @ViewBuilder
    private func downloadMark(_ index: Int) -> some View {
        let _ = app.downloads.changes
        if let book, let position = position(of: index, in: book) {
            if app.downloads.isActive(book.id, position) {
                if let progress = app.downloads.progress, progress.total > 0 {
                    ProgressView(value: Double(progress.done), total: Double(progress.total)).frame(width: 36).accessibilityLabel("Downloading")
                } else {
                    ProgressView().accessibilityLabel("Downloading")
                }
            } else if app.downloads.isWaiting(book.id, position) {
                Image(systemName: "clock").foregroundStyle(Palette.textSecondary).accessibilityLabel("Waiting to download")
            } else if app.isDownloaded(book.id, index: position) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent).accessibilityLabel("Downloaded")
            }
        }
    }

    /// The place of a chapter of the source in the book.
    private func position(of index: Int, in book: Book) -> Int? {
        guard let details, details.chapters.indices.contains(index) else { return nil }
        return app.novel(of: book)?.chapters.firstIndex { $0.remote == details.chapters[index].id }
    }

    private func isCurrent(_ index: Int) -> Bool {
        guard let book, book.lastRead != nil else { return false }
        return book.page == index
    }

    /// The source of the chosen hit, for its covers and its chapters.
    private func prepare() async {
        source = nil
        guard let installed else { return }
        source = try? await app.load(installed)
        if let book { try? await app.refresh(book) }
    }

    /// Asks each source for the title at the same time. The source of a book in the library wins,
    /// so that the place of the user stays. Else the source with the most chapters wins.
    private func load() async {
        answers = [:]
        faults = [:]
        if let kept = hits.first(where: { hasBook($0) }), !userChose { chosen = kept }
        comparing = true
        await ask(hits)
        comparing = false
        if !userChose && !hits.contains(where: hasBook), hits.count > 1,
           let best = SourceChoice.best(hits.map { ($0.source, answers[$0.source].map { SourceChoice.distinctChapters($0.chapters) }) }),
           let hit = hits.first(where: { $0.source == best }) {
            chosen = hit
        }
        if findOthers { await addOthers() }
    }

    private func ask(_ asked: [SearchHit]) async {
        await withTaskGroup(of: (String, Result<OnlineDetails, Error>).self) { group in
            for hit in asked {
                guard let installed = app.library.installed.first(where: { $0.id == hit.source }) else { continue }
                group.addTask { (hit.source, await Self.details(of: hit, in: installed, app: app)) }
            }
            for await (id, result) in group {
                switch result {
                case let .success(details): answers[id] = details
                case let .failure(error): faults[id] = error.localizedDescription
                }
            }
        }
    }

    private static func details(of hit: SearchHit, in installed: InstalledSource, app: AppModel) async -> Result<OnlineDetails, Error> {
        do {
            return .success(try await app.load(installed).details(of: hit.series))
        } catch {
            return .failure(error)
        }
    }

    /// Searches the other sources of the same kind for the same title, and adds them to the Source menu.
    private func addOthers() async {
        let key = TitleMatch.key(series.title)
        let novels = app.library.installed.first { $0.id == chosen.source }?.info.novels
        let others = app.library.installed.filter { other in other.info.novels == novels && !hits.contains { $0.source == other.id } }
        let found = await app.search(series.title, in: others, limit: 4)
        let extra = found.compactMap { hits in hits.first { TitleMatch.key($0.series.title) == key } }
        guard !extra.isEmpty else { return }
        hits += extra
        await ask(extra)
    }

    private func hasBook(_ hit: SearchHit) -> Bool {
        guard let installed = app.library.installed.first(where: { $0.id == hit.source }) else { return false }
        return app.library.book(from: BookOrigin(list: installed.list, source: installed.info.id, series: hit.series.id)) != nil
    }

    @discardableResult
    private func add(_ details: OnlineDetails, listed: Bool) async -> Book? {
        guard let installed else { return nil }
        adding = true
        defer { adding = false }
        do {
            return try await app.add(details, from: installed, listed: listed)
        } catch {
            app.fault = "The series was not added: \(error.localizedDescription)"
            return nil
        }
    }

    /// Puts the title in the read list, or takes it out. A book with no place leaves the library.
    private func toggleList(_ details: OnlineDetails) async {
        if let book, book.listed {
            if book.lastRead == nil { app.delete(book) } else { app.update(book.id) { $0.listed = false } }
        } else {
            await add(details, listed: true)
        }
    }

    /// A chapter opens in the reader. The series goes into the library first, so that the place stays.
    private func open(chapter index: Int, details: OnlineDetails) async {
        guard let book = await add(details, listed: false) else { return }
        // The chapter of the source is at the same place in the book, because the book has all of them in order.
        let position = (try? Novel.load(from: app.folder(of: book)))?.chapters.firstIndex { $0.remote == details.chapters[index].id } ?? index
        app.update(book.id) { $0.read(chapter: position, position: 0) }
        reading = app.book(book.id)
    }
}
