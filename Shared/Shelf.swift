import Foundation

/// The books of Continue reading that the widget shows. The app writes them into the App Group,
/// and the widget reads them. With no App Group, the shelf is empty.
struct Shelf: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        var id: UUID
        var title: String
        /// "Page 3 of 20" or "Chapter 2 of 9".
        var place: String
        var progress: Double
        /// The file name of the small cover in the folder of the shelf.
        var cover: String?
    }

    var items: [Item] = []

    static let group = "group.io.github.stivengjekaj.asabunko"
    static let widgetKind = "ContinueReading"

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("Shelf", isDirectory: true)
    }

    static func load() -> Shelf {
        guard let file = folder?.appendingPathComponent("shelf.json"), let data = try? Data(contentsOf: file),
              let shelf = try? JSONDecoder().decode(Shelf.self, from: data) else { return Shelf() }
        return shelf
    }

    func save() throws {
        guard let folder = Self.folder else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: folder.appendingPathComponent("shelf.json"), options: .atomic)
    }

    /// The link that opens a book in the app.
    static func link(to id: UUID) -> URL { URL(string: "asabunko://open/\(id.uuidString)")! }

    /// The book of a link, or nil for another URL.
    static func book(in url: URL) -> UUID? {
        guard url.scheme == "asabunko", url.host == "open" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
