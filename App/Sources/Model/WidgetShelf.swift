import AsaCore
import UIKit
import WidgetKit

extension AppModel {
    /// Writes the first books of Continue reading for the widget, with a small cover of each.
    /// The widget reloads only when the shelf changes.
    func updateShelf() {
        guard let folder = Shelf.folder else { return }
        let items = library.continueReading.prefix(4).map { book in
            Shelf.Item(
                id: book.id, title: book.title,
                place: book.format == .comic || book.format == .pdf ? "Page \(book.page + 1) of \(book.pageCount)" : "Chapter \(book.page + 1) of \(book.pageCount)",
                progress: book.progress, cover: "\(book.id.uuidString).jpg"
            )
        }
        let shelf = Shelf(items: Array(items))
        guard shelf != Shelf.load() else { return }
        let covers = items.map { (cover(of: book($0.id)!), folder.appendingPathComponent($0.cover!)) }
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (source, target) in covers where !FileManager.default.fileExists(atPath: target.path) {
                Self.writeSmallCover(from: source, to: target)
            }
            try? shelf.save()
            WidgetCenter.shared.reloadTimelines(ofKind: Shelf.widgetKind)
        }
    }

    /// A widget has a small memory limit, so it gets covers of 300 points of height at most.
    private nonisolated static func writeSmallCover(from source: URL, to target: URL) {
        guard let image = UIImage(contentsOfFile: source.path) else { return }
        let scale = min(1, 300 / max(image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let small = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        try? small.jpegData(compressionQuality: 0.8)?.write(to: target, options: .atomic)
    }
}
