import Foundation

/// Finds one title in many sources. Two sources can write the same title in a different form.
public enum TitleMatch {
    /// The title with only its letters and digits, in lowercase and with no accents.
    public static func key(_ title: String) -> String {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// How well a title agrees with a search: 3 for the same title, 2 when it starts with the search,
    /// 1 when it holds the search, and 0 when it does not.
    public static func score(_ title: String, query: String) -> Int {
        let title = key(title)
        let query = key(query)
        guard !query.isEmpty else { return 0 }
        if title == query { return 3 }
        if title.hasPrefix(query) { return 2 }
        if title.contains(query) { return 1 }
        return 0
    }
}

/// One series in one source.
public struct SearchHit: Sendable, Hashable {
    /// The ID of the installed source.
    public var source: String
    public var series: OnlineSeries

    public init(source: String, series: OnlineSeries) {
        self.source = source
        self.series = series
    }
}

/// One title of a search, with each source that has it.
public struct SearchGroup: Sendable, Hashable, Identifiable {
    public var id: String { key }
    public var key: String
    /// The title as the first source writes it.
    public var title: String
    /// The first cover that a source gives.
    public var cover: SearchHit?
    public var hits: [SearchHit]
}

/// The results of a search in many sources. The results of each source come in at a different time.
public struct SearchResults: Sendable {
    public let query: String
    private var groups: [SearchGroup] = []
    private var index: [String: Int] = [:]

    public init(query: String) {
        self.query = query
    }

    /// Adds the series of one source. A series with the same title as a series of another source goes into its group.
    public mutating func add(_ items: [OnlineSeries], from source: String) {
        for series in items {
            let key = TitleMatch.key(series.title)
            guard !key.isEmpty else { continue }
            let hit = SearchHit(source: source, series: series)
            if let at = index[key] {
                // One source can give the same title two times. The group keeps the first.
                guard !groups[at].hits.contains(where: { $0.source == source }) else { continue }
                groups[at].hits.append(hit)
                if groups[at].cover == nil, series.cover != nil { groups[at].cover = hit }
            } else {
                index[key] = groups.count
                groups.append(SearchGroup(key: key, title: series.title, cover: series.cover == nil ? nil : hit, hits: [hit]))
            }
        }
    }

    /// The groups, with the best match first: the same title, then the title that more sources have,
    /// then the order in which the results came.
    public var sorted: [SearchGroup] {
        groups.enumerated().sorted { a, b in
            let scoreA = TitleMatch.score(a.element.title, query: query)
            let scoreB = TitleMatch.score(b.element.title, query: query)
            if scoreA != scoreB { return scoreA > scoreB }
            if a.element.hits.count != b.element.hits.count { return a.element.hits.count > b.element.hits.count }
            return a.offset < b.offset
        }.map(\.element)
    }
}

/// Chooses the source of a title.
public enum SourceChoice {
    /// The source with the most chapters. When two sources have the same number, the first one wins.
    /// A source with no answer has nil.
    public static func best(_ chapters: [(source: String, count: Int?)]) -> String? {
        var best: (source: String, count: Int)?
        for entry in chapters {
            guard let count = entry.count, count > 0 else { continue }
            if best == nil || count > best!.count { best = (entry.source, count) }
        }
        return best?.source ?? chapters.first?.source
    }
}
