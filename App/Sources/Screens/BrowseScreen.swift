import AsaCore
import SwiftUI

/// The places to find books: the sources of the user, by kind.
struct BrowseScreen: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            List {
                if app.library.sources.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("No sources yet").font(Karla.font(18, .bold))
                            Text("Asabunko comes with no sources. Paste the URLs of your catalogs and source lists, one on each line.")
                                .font(Karla.font(15)).foregroundStyle(Palette.textSecondary)
                            NavigationLink("Add sources") { SourcesScreen() }
                                .buttonStyle(PillButtonStyle())
                        }
                        .padding(.vertical, 8)
                    }
                }
                if !app.library.installed.isEmpty {
                    Section("Installed") {
                        ForEach(app.library.installed) { installed in
                            NavigationLink { OnlineSourceScreen(installed: installed) } label: {
                                HStack(spacing: 12) {
                                    SourceIcon(url: installed.info.icon)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(installed.info.name).font(Karla.font(16, .bold))
                                        Text(installed.info.language + (installed.info.novels ? " · Novels" : " · Comics"))
                                            .font(Karla.font(12)).foregroundStyle(Palette.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                }
                ForEach(groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.links) { link in
                            NavigationLink { destination(link) } label: { SourceRow(link: link) }
                        }
                    }
                }
            }
            .asaForm()
            .asaScreen()
            .navigationTitle("Browse")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SourcesScreen() } label: { Text("Sources").font(Karla.font(16, .bold)) }
                }
            }
        }
    }

    private var groups: [(title: String, links: [SourceLink])] {
        let kinds: [SourceKind?] = SourceKind.allCases + [nil]
        return kinds.compactMap { kind in
            let links = app.library.sources.filter { $0.kind == kind }
            return links.isEmpty ? nil : (kind?.name ?? "Unknown kind", links)
        }
    }

    @ViewBuilder
    private func destination(_ link: SourceLink) -> some View {
        switch link.kind {
        case .opds: OPDSFeedScreen(source: link, url: link.url, title: link.name ?? link.url.host ?? "Catalog")
        case .lnreader, .suwayomi, .aidoku: SourceListScreen(link: link)
        case nil: DetectScreen(link: link)
        case let .some(kind): ContentUnavailableView(
            "Not in this version", systemImage: "clock",
            description: Text("Asabunko reads \(kind.name.lowercased()) in a later version. The line stays in your list.")
        ).asaScreen()
        }
    }
}

/// One source, with its name and only the host of its URL.
struct SourceRow: View {
    let link: SourceLink

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(link.name ?? link.url.host ?? "Source").font(Karla.font(16, .bold))
                Text((link.username.map { "\($0) at " } ?? "") + link.shortAddress)
                    .font(Karla.font(13)).foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
        } icon: {
            Image(systemName: link.kind?.symbol ?? "questionmark.circle").foregroundStyle(Palette.accent)
        }
    }
}

extension SourceKind {
    var symbol: String {
        switch self {
        case .opds: "server.rack"
        case .lnreader: "text.book.closed"
        case .aidoku: "square.stack.3d.up"
        case .paperback: "books.vertical.circle"
        case .suwayomi: "desktopcomputer"
        }
    }
}

/// Reads a source with no known kind and finds its kind from what it gives.
private struct DetectScreen: View {
    let link: SourceLink
    @Environment(AppModel.self) private var app
    @State private var fault: String?

    var body: some View {
        Group {
            if let fault {
                ContentUnavailableView("Unknown source", systemImage: "questionmark.circle", description: Text(fault))
            } else {
                ProgressView()
            }
        }
        .asaScreen()
        .task {
            do {
                let data = try await Network.data(for: AppModel.request(link.url, source: link))
                if let kind = SourceKind.detect(data) {
                    app.learn(link.id, kind: kind, name: nil)
                } else {
                    fault = "The URL does not give an OPDS catalog or a source list that Asabunko knows."
                }
            } catch {
                fault = error.localizedDescription
            }
        }
    }
}

/// The source list as text, one URL on each line, as in ZettaStream. Save replaces the full list.
struct SourcesScreen: View {
    @Environment(AppModel.self) private var app
    @State private var draft = ""
    @State private var loaded = false
    @State private var saved: String?
    @FocusState private var editing: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste one URL on each line. Asabunko finds the kind of each source.")
                    .font(Karla.font(15)).foregroundStyle(Palette.textSecondary)
                kinds
                TextEditor(text: $draft)
                    .focused($editing)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(8)
                    // A long list scrolls inside the editor, so Save and Paste stay near it.
                    .frame(height: 220)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(editing ? Palette.accent : Palette.outline))
                    .accessibilityLabel("Source list")
                Text("The new list replaces the old list. To remove a source, remove its line. For a server with an account, write https://user:password@host/... The password goes to the Keychain, and the list shows only the user name.")
                    .font(Karla.font(13)).foregroundStyle(Palette.textSecondary)
                HStack(spacing: 10) {
                    Button("Save", action: save).buttonStyle(PillButtonStyle())
                    // The system paste button reads the clipboard with no prompt. A plain
                    // button that reads UIPasteboard gets no text until the user permits it.
                    PasteButton(payloadType: String.self) { texts in
                        Task { @MainActor in draft = texts.joined(separator: "\n") }
                    }
                    .labelStyle(.titleOnly)
                    .tint(Palette.surfaceHigh)
                    .foregroundStyle(Palette.textPrimary)
                }
                if let saved {
                    Text(saved).font(Karla.font(14)).foregroundStyle(Palette.accent)
                }
                Text("Current list (\(app.library.sources.count))").font(Karla.font(18, .bold)).padding(.top, 8)
                ForEach(app.library.sources) { link in
                    SourceRow(link: link).frame(maxWidth: .infinity, alignment: .leading).card()
                }
            }
            .padding(gutter)
        }
        .scrollDismissesKeyboard(.interactively)
        .asaScreen()
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editing = false }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            draft = SourceList.format(app.library.sources)
        }
    }

    private var kinds: some View {
        let rows: [(String, String)] = [
            ("An OPDS catalog: Komga, Kavita, Calibre-web", "https://.../opds/v1.2/catalog"),
            ("LNReader plugins, for web novels", "https://.../plugins.min.json"),
            ("Aidoku sources", "https://.../index.min.json"),
            ("Paperback 0.9 extensions", "https://.../versioning.json"),
            ("A Suwayomi server, for Mihon extensions", "http://...:4567"),
        ]
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.0) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.0).font(Karla.font(14, .bold))
                    Text(row.1).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Palette.surfaceHigh, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private func save() {
        editing = false
        let list = app.saveSources(draft)
        draft = SourceList.format(list)
        saved = "Saved \(list.count) source" + (list.count == 1 ? "" : "s") + "."
    }
}

/// One page of an OPDS catalog.
struct OPDSFeedScreen: View {
    let source: SourceLink
    @Environment(AppModel.self) private var app
    let url: URL
    let title: String
    @State private var feed: OPDSFeed?
    @State private var fault: String?
    @State private var loadingMore = false
    @State private var query = ""
    @State private var results: OPDSFeed?

    var body: some View {
        ScrollView {
            if let fault {
                ContentUnavailableView("The catalog did not open", systemImage: "wifi.exclamationmark", description: Text(fault))
                    .padding(.top, 60)
            } else if let shown = results ?? feed {
                content(shown).padding(.horizontal, gutter).padding(.bottom, 32)
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .asaScreen()
        .navigationTitle(results == nil ? (feed?.title ?? title) : "Results")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(SearchModifier(enabled: feed?.search != nil, query: $query, onSubmit: search, onClear: { results = nil }))
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func content(_ feed: OPDSFeed) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if !feed.navigation.isEmpty { links(feed.navigation) }
            ForEach(Array(feed.groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 12) {
                    if !group.title.isEmpty { Text(group.title).font(Karla.font(19, .bold)) }
                    if !group.navigation.isEmpty { links(group.navigation) }
                    if !group.publications.isEmpty { grid(group.publications) }
                }
            }
            if !feed.publications.isEmpty { grid(feed.publications) }
            if feed.navigation.isEmpty && feed.publications.isEmpty && feed.groups.isEmpty {
                ContentUnavailableView("Nothing here", systemImage: "tray", description: Text("This page of the catalog is empty."))
            }
            if feed.next != nil {
                Button(loadingMore ? "Loading" : "Load more") { Task { await loadMore() } }
                    .buttonStyle(PillButtonStyle())
                    .frame(maxWidth: .infinity)
                    .disabled(loadingMore)
            }
        }
        .padding(.top, 8)
    }

    private func links(_ links: [OPDSLink]) -> some View {
        VStack(spacing: 0) {
            ForEach(links, id: \.self) { link in
                NavigationLink {
                    OPDSFeedScreen(source: source, url: link.url, title: link.title)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.title).font(Karla.font(16, .medium))
                            if let summary = link.summary {
                                Text(summary).font(Karla.font(13)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if link != links.last { Divider().overlay(Palette.outline) }
            }
        }
        .padding(.horizontal, 16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(Palette.outline, lineWidth: 0.5))
    }

    private func grid(_ publications: [OPDSPublication]) -> some View {
        CoverGrid(
            items: publications,
            title: \.title,
            subtitle: \.author,
            cover: { $0.image.map { AppModel.request($0, source: source) } },
            destination: { PublicationScreen(source: source, publication: $0) }
        )
    }

    private func fetch(_ url: URL) async throws -> OPDSFeed {
        try OPDS.parse(try await Network.data(for: AppModel.request(url, source: source)), base: url)
    }

    private func load() async {
        do {
            feed = try await fetch(url)
            fault = nil
            if url == source.url { app.learn(source.id, kind: .opds, name: feed?.title) }
        } catch OPDSError.notAFeed {
            fault = "The address does not give an OPDS feed. Check the URL of the catalog."
        } catch {
            fault = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard let next = (results ?? feed)?.next else { return }
        loadingMore = true
        defer { loadingMore = false }
        guard let page = try? await fetch(next) else { return }
        if results != nil {
            results?.publications += page.publications
            results?.next = page.next
        } else {
            feed?.publications += page.publications
            feed?.navigation += page.navigation
            feed?.next = page.next
        }
    }

    private func search() {
        guard let search = feed?.search, !query.isEmpty else { return }
        Task {
            var template: String?
            switch search {
            case let .template(text): template = text
            case let .description(url):
                template = (try? await Network.data(for: AppModel.request(url, source: source))).flatMap(OPDS.openSearchTemplate)
            }
            guard let template, let url = OPDS.searchURL(template: template, query: query) else { return }
            results = try? await fetch(url)
        }
    }
}

/// The search field, only when the page can search.
private struct SearchModifier: ViewModifier {
    let enabled: Bool
    @Binding var query: String
    let onSubmit: () -> Void
    let onClear: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
                .onSubmit(of: .search, onSubmit)
                .onChange(of: query) { _, text in if text.isEmpty { onClear() } }
        } else {
            content
        }
    }
}

/// One book of a catalog, with a button to read it now and a button to download it.
struct PublicationScreen: View {
    let source: SourceLink
    let publication: OPDSPublication
    @Environment(AppModel.self) private var app
    @State private var reading = false
    @State private var downloading = false
    @State private var downloaded = false
    @State private var page = 0
    @State private var mode = ReadingMode.rightToLeft

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    RemoteCover(request: publication.image.map { AppModel.request($0, source: source) }, title: publication.title)
                        .frame(width: 120)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(publication.title).font(Karla.font(20, .bold))
                        if let author = publication.author {
                            Text(author).font(Karla.font(15)).foregroundStyle(Palette.textSecondary)
                        }
                        if let stream = publication.stream, stream.count > 0 {
                            Text("\(stream.count) pages").font(Karla.font(13)).foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
                HStack(spacing: 12) {
                    if publication.stream != nil {
                        Button("Read now") { reading = true }.buttonStyle(PillButtonStyle())
                    }
                    if let download = publication.download {
                        Button(downloaded ? "In the library" : downloading ? "Downloading" : "Download") {
                            downloading = true
                            Task {
                                await app.download(AppModel.request(download.url, source: source), title: publication.title, fileExtension: download.fileExtension)
                                downloading = false
                                downloaded = app.fault == nil
                            }
                        }
                        .buttonStyle(PillButtonStyle())
                        .disabled(downloading || downloaded)
                    }
                }
                if publication.stream == nil && publication.download == nil {
                    Text("Asabunko cannot read the files of this book.").font(Karla.font(14)).foregroundStyle(Palette.textSecondary)
                }
                if let summary = publication.summary {
                    Text(summary).font(Karla.font(15)).foregroundStyle(Palette.textPrimary.opacity(0.9))
                }
            }
            .padding(gutter)
        }
        .asaScreen()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { mode = app.library.defaultMode }
        .fullScreenCover(isPresented: $reading) {
            PageReader(title: publication.title, content: streamContent, page: $page, mode: $mode)
        }
    }

    private var streamContent: PageContent? {
        guard let stream = publication.stream else { return nil }
        return .images((0..<stream.count).compactMap { stream.url(page: $0) }.map { .remote(AppModel.request($0, source: source)) })
    }
}
