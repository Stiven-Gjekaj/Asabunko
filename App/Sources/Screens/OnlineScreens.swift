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
    }

    private func row(_ info: SourceInfo) -> some View {
        HStack(spacing: 12) {
            SourceIcon(url: info.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.name).font(Karla.font(16, .bold))
                Text("Version \(info.version)" + (info.adult ? " · 18+" : "")).font(Karla.font(12)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            if working.contains(info.id) {
                ProgressView()
            } else if app.isInstalled(info, from: link) {
                Button("Remove") {
                    if let installed = app.library.installed.first(where: { $0.list == link.id && $0.info.id == info.id }) { app.uninstall(installed) }
                }
                .font(Karla.font(14, .bold))
                .foregroundStyle(Palette.danger)
                .buttonStyle(.borderless)
            } else {
                Button("Install") {
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

    enum Listing: String, CaseIterable { case popular = "Popular", latest = "Latest" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if searching.isEmpty, source?.canShowLatest == true {
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
        .task {
            guard source == nil else { return }
            do {
                source = try await app.load(installed)
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
            if !searching.isEmpty {
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

/// A series or a novel of a source: its facts, its chapters, and a button to add it to the library.
struct OnlineSeriesScreen: View {
    let installed: InstalledSource
    let series: OnlineSeries
    @Environment(AppModel.self) private var app
    @State private var source: OnlineSource?
    @State private var details: OnlineDetails?
    @State private var fault: String?
    @State private var adding = false
    @State private var reading: Book?
    @State private var newestFirst = false

    private var book: Book? {
        app.library.book(from: BookOrigin(list: installed.list, source: installed.info.id, series: series.id))
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
                        Text(installed.info.name).font(Karla.font(13)).foregroundStyle(Palette.accent)
                    }
                }
                .listRowBackground(Color.clear)
                if let details {
                    HStack(spacing: 10) {
                        if let book {
                            Button(book.lastRead == nil ? "Start reading" : "Continue") { reading = book }.buttonStyle(PillButtonStyle())
                        } else {
                            Button(adding ? "Adding" : "Add to library") { Task { await add(details, open: false) } }
                                .buttonStyle(PillButtonStyle()).disabled(adding)
                        }
                    }
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
                Section {
                    ForEach(newestFirst ? Array(details.chapters.enumerated().reversed()) : Array(details.chapters.enumerated()), id: \.element.id) { index, chapter in
                        Button { Task { await open(chapter: index, details: details) } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chapter.title).font(Karla.font(15, isCurrent(index) ? .bold : .regular))
                                    if let date = chapter.date { Text(date).font(Karla.font(12)).foregroundStyle(Palette.textSecondary) }
                                }
                                Spacer()
                                if isCurrent(index) { Image(systemName: "bookmark.fill").foregroundStyle(Palette.accent) }
                            }
                        }
                        .listRowBackground(Palette.surface)
                    }
                } header: {
                    HStack {
                        Text("\(details.chapters.count) chapters")
                        Spacer()
                        Button(newestFirst ? "Oldest first" : "Newest first") { newestFirst.toggle() }.font(Karla.font(13, .bold))
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .asaForm()
        .asaScreen()
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .fullScreenCover(item: $reading) { book in
            switch book.format {
            case .novel: NovelReaderScreen(bookID: book.id)
            default: SeriesReaderScreen(bookID: book.id)
            }
        }
    }

    private func isCurrent(_ index: Int) -> Bool {
        guard let book, book.lastRead != nil else { return false }
        return book.page == index
    }

    private func load() async {
        do {
            let loaded = try await app.load(installed)
            source = loaded
            details = try await loaded.details(of: series)
            fault = nil
            if let book { try? await app.refresh(book) }
        } catch {
            fault = error.localizedDescription
        }
    }

    @discardableResult
    private func add(_ details: OnlineDetails, open: Bool) async -> Book? {
        adding = true
        defer { adding = false }
        do {
            return try await app.add(details, from: installed)
        } catch {
            app.fault = "The series was not added: \(error.localizedDescription)"
            return nil
        }
    }

    /// A chapter opens in the reader. The series goes into the library first, so that the place stays.
    private func open(chapter index: Int, details: OnlineDetails) async {
        guard let book = await add(details, open: true) else { return }
        // The chapter of the source is at the same place in the book, because the book has all of them in order.
        let position = (try? Novel.load(from: app.folder(of: book)))?.chapters.firstIndex { $0.remote == details.chapters[index].id } ?? index
        app.update(book.id) { $0.read(chapter: position, position: 0) }
        reading = app.book(book.id)
    }
}
