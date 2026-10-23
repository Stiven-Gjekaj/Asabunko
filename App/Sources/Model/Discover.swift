import AsaCore
import Foundation
import Observation

/// The titles of Discover: the popular and the latest titles of the installed sources.
@MainActor
@Observable
final class DiscoverFeed {
    /// One title of a row, with the request of its cover.
    struct Item: Identifiable, Hashable {
        var hit: SearchHit
        var cover: URLRequest?
        var sourceName: String
        var id: String { hit.source + "|" + hit.series.id }
    }

    /// One title of the banner, with its facts from the source.
    struct Featured: Identifiable {
        var item: Item
        var details: OnlineDetails?
        var id: String { item.id }
    }

    struct Row: Identifiable {
        var id: String
        var title: String
        var items: [Item]
    }

    private(set) var featured: [Featured] = []
    private(set) var rows: [Row] = []
    private(set) var loading = false
    /// The installed sources of the last load. A change of the sources loads the feed again.
    private var loadedFor: [String] = []

    /// The most sources that Discover asks, so that the page opens fast.
    private static let sourceLimit = 10

    /// All covers of the feed, for the art of the empty screens.
    var covers: [URLRequest] {
        var seen: Set<String> = []
        return (featured.map(\.item) + rows.flatMap(\.items)).compactMap { item in
            guard let cover = item.cover, seen.insert(item.id).inserted else { return nil }
            return cover
        }
    }

    /// The load that runs now. A new load stops it, such as when more sources install.
    private var current: Task<Void, Never>?
    private var generation = 0

    func load(_ app: AppModel, force: Bool = false) async {
        let installed = Array(app.library.installed.prefix(Self.sourceLimit))
        guard force || installed.map(\.id) != loadedFor else { return }
        current?.cancel()
        generation += 1
        let mine = generation
        loading = true
        let task = Task { await fetch(app, installed) }
        current = task
        await task.value
        if mine == generation { loading = false }
    }

    private func fetch(_ app: AppModel, _ installed: [InstalledSource]) async {
        guard !installed.isEmpty else {
            rows = []
            featured = []
            loadedFor = []
            return
        }

        var popular: [(InstalledSource, [Item])] = []
        var latest: [(InstalledSource, [Item])] = []
        await withTaskGroup(of: (InstalledSource, [Item], [Item]).self) { group in
            for source in installed {
                group.addTask { await self.lists(of: source, app: app) }
            }
            for await (source, top, new) in group {
                if !top.isEmpty { popular.append((source, top)) }
                if !new.isEmpty { latest.append((source, new)) }
            }
        }
        // The order of the rows follows the order of the sources, not the order of the answers.
        let order = Dictionary(uniqueKeysWithValues: installed.enumerated().map { ($1.id, $0) })
        popular.sort { order[$0.0.id, default: 0] < order[$1.0.id, default: 0] }
        latest.sort { order[$0.0.id, default: 0] < order[$1.0.id, default: 0] }

        var next: [Row] = []
        let byID = Dictionary((popular + latest).flatMap(\.1).map { ($0.hit, $0) }, uniquingKeysWith: { a, _ in a })
        func mixed(_ lists: [(InstalledSource, [Item])], limit: Int) -> [Item] {
            TitleMix.roundRobin(lists.map { $0.1.map(\.hit) }, limit: limit).compactMap { byID[$0] }
        }
        let comics = mixed(popular.filter { !$0.0.info.novels }, limit: 24)
        let novels = mixed(popular.filter { $0.0.info.novels }, limit: 24)
        if !comics.isEmpty { next.append(Row(id: "comics", title: "Popular comics", items: comics)) }
        if !novels.isEmpty { next.append(Row(id: "novels", title: "Popular novels", items: novels)) }
        let updates = mixed(latest, limit: 24)
        if !updates.isEmpty { next.append(Row(id: "latest", title: "New chapters", items: updates)) }
        for (source, items) in popular where popular.count > 1 {
            next.append(Row(id: "source:" + source.id, title: "Popular on \(source.info.name)", items: items))
        }
        // A load that a newer load stopped does not write its rows.
        guard !Task.isCancelled else { return }
        rows = next
        loadedFor = installed.map(\.id)

        // The banner shows the first titles of the mix, with their summary and their genres.
        let top = Array(mixed(popular, limit: 5))
        featured = top.map { Featured(item: $0, details: nil) }
        await withTaskGroup(of: (Int, OnlineDetails?).self) { group in
            for (index, item) in top.enumerated() {
                guard let source = installed.first(where: { $0.id == item.hit.source }) else { continue }
                group.addTask { (index, await self.details(of: item, in: source, app: app)) }
            }
            for await (index, details) in group where featured.indices.contains(index) && !Task.isCancelled {
                featured[index].details = details
            }
        }
    }

    /// The popular and the latest titles of one source.
    private func lists(of source: InstalledSource, app: AppModel) async -> (InstalledSource, [Item], [Item]) {
        guard let loaded = try? await app.load(source) else { return (source, [], []) }
        func items(_ page: OnlinePage?) -> [Item] {
            (page?.items ?? []).prefix(20).map {
                Item(hit: SearchHit(source: source.id, series: $0), cover: $0.cover.map(loaded.imageRequest), sourceName: source.info.name)
            }
        }
        let top = items(try? await loaded.popular(page: 1))
        let new = loaded.canShowLatest ? items(try? await loaded.latest(page: 1)) : []
        return (source, top, new)
    }

    private func details(of item: Item, in source: InstalledSource, app: AppModel) async -> OnlineDetails? {
        guard let loaded = try? await app.load(source) else { return nil }
        return try? await loaded.details(of: item.hit.series)
    }
}
