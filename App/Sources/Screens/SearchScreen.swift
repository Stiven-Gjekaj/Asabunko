import AsaCore
import SwiftUI

/// The state of the search. It lives as long as the tab, so that Back from a title shows the same results.
@MainActor
@Observable
final class SearchModel {
    var text = ""
    /// The text of the last search. The search starts when the user presses Search, not while the user types.
    private(set) var query = ""
    private(set) var results = SearchResults(query: "")
    private(set) var searching = false
    private(set) var asked = 0
    private(set) var answered = 0
    private var task: Task<Void, Never>?

    /// Searches all installed sources. The results come as each source answers.
    func search(_ app: AppModel) {
        let next = text.trimmingCharacters(in: .whitespacesAndNewlines)
        task?.cancel()
        query = next
        results = SearchResults(query: next)
        guard !next.isEmpty else {
            searching = false
            return
        }
        let sources = app.library.installed
        asked = sources.count
        answered = 0
        searching = true
        RecentSearches.add(next)
        task = Task { [weak self] in
            await app.search(next, in: sources) { id, items in
                guard let self, !Task.isCancelled, self.query == next else { return }
                self.results.add(items, from: id)
                self.answered += 1
            }
            guard let self, !Task.isCancelled else { return }
            self.searching = false
        }
    }

    func clear() {
        task?.cancel()
        text = ""
        query = ""
        results = SearchResults(query: "")
        searching = false
    }
}

/// The recent searches, newest first, on this device.
enum RecentSearches {
    static let key = "search.recent"

    static var all: [String] {
        (UserDefaults.standard.string(forKey: key) ?? "").split(separator: "\n").map(String.init)
    }

    static func add(_ query: String) {
        let list = [query] + all.filter { $0.caseInsensitiveCompare(query) != .orderedSame }
        UserDefaults.standard.set(list.prefix(12).joined(separator: "\n"), forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Search in all sources at the same time, as in ZettaStream. A title that many sources have shows one time.
struct SearchScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model = SearchModel()
    @State private var kind = Kind.all
    @AppStorage(RecentSearches.key) private var recentText = ""
    @FocusState private var focused: Bool

    enum Kind: String, CaseIterable { case all = "All", comics = "Comics", novels = "Novels" }

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 16, alignment: .top)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Search").font(Karla.font(32, .bold, relativeTo: .largeTitle)).accessibilityAddTraits(.isHeader)
                    field
                    if model.searching {
                        ProgressView(value: Double(model.answered), total: Double(max(model.asked, 1)))
                            .tint(Palette.accent)
                            .accessibilityLabel("Searching \(model.asked) sources")
                    }
                    content
                }
                .padding(.horizontal, gutter)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.immediately)
            .asaScreen()
            .toolbar(.hidden, for: .navigationBar)
            .task { await app.discover.load(app) }
        }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.textSecondary)
            TextField("", text: $model.text, prompt: Text("Search titles").foregroundColor(Palette.textSecondary))
                .font(Karla.font(16))
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focused)
                .onSubmit { model.search(app) }
                .accessibilityLabel("Search titles")
            if !model.text.isEmpty {
                Button { model.clear() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textSecondary).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.leading, 14)
        .frame(minHeight: 52)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(focused ? Palette.accent : Palette.outline, lineWidth: focused ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    @ViewBuilder
    private var content: some View {
        let groups = shown
        if app.library.installed.isEmpty {
            EmptyArt(covers: [], title: "No sources yet", text: "Search asks your installed sources. Add a source list in Settings, Sources, and Asabunko installs its sources.") {
                NavigationLink { SourcesHomeScreen() } label: { Text("Add sources") }.buttonStyle(PillButtonStyle())
            }
        } else if model.query.isEmpty {
            if !recent.isEmpty { recentSearches }
            EmptyArt(covers: app.discover.covers, title: "Find a manga or a novel",
                     text: "Type a title and press Search. Asabunko asks your \(app.library.installed.count) sources at the same time.")
        } else {
            kindPicker
            if groups.isEmpty && !model.searching {
                EmptyArt(covers: [], title: "Nothing found", text: "No source found \"\(model.query)\".")
            } else if !groups.isEmpty {
                Text("\(groups.count) title\(groups.count == 1 ? "" : "s") for \"\(model.query)\"")
                    .font(Karla.font(14)).foregroundStyle(Palette.textSecondary)
                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(groups) { group in
                        NavigationLink { OnlineSeriesScreen(hits: group.hits) } label: { tile(group) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var kindPicker: some View {
        Picker("Kind", selection: $kind) {
            ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private func tile(_ group: SearchGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteCover(request: cover(of: group), title: group.title)
                .overlay(alignment: .topTrailing) {
                    if group.hits.count > 1 {
                        Text("\(group.hits.count)")
                            .font(Karla.font(12, .bold))
                            .foregroundStyle(Palette.onAccent)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Palette.accent, in: Capsule())
                            .padding(6)
                    }
                }
            Text(group.title).font(Karla.font(14, .bold)).lineLimit(2).multilineTextAlignment(.leading)
            Text(group.hits.count == 1 ? name(group.hits[0].source) : "\(group.hits.count) sources")
                .font(Karla.font(12)).foregroundStyle(Palette.textSecondary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var recent: [String] { recentText.split(separator: "\n").map(String.init) }

    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent searches").font(Karla.font(17, .bold)).accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: 8) {
                ForEach(recent, id: \.self) { past in
                    Button {
                        model.text = past
                        model.search(app)
                    } label: {
                        Label(past, systemImage: "clock.arrow.circlepath").lineLimit(1)
                    }
                    .font(Karla.font(14, .medium))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(Palette.surfaceHigh, in: Capsule())
                    .buttonStyle(.plain)
                }
                Button("Clear") { RecentSearches.clear() }
                    .font(Karla.font(14, .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear the recent searches")
            }
        }
    }

    /// The groups of the chosen kind: comics, novels, or all.
    private var shown: [SearchGroup] {
        let groups = model.results.sorted
        guard kind != .all else { return groups }
        return groups.filter { group in
            app.library.installed.first { $0.id == group.hits[0].source }?.info.novels == (kind == .novels)
        }
    }

    private func name(_ source: String) -> String {
        app.library.installed.first { $0.id == source }?.info.name ?? "Source"
    }

    private func cover(of group: SearchGroup) -> URLRequest? {
        guard let hit = group.cover, let url = hit.series.cover else { return nil }
        return LoadedSources.shared.get(hit.source)?.imageRequest(url) ?? URLRequest(url: url)
    }
}
