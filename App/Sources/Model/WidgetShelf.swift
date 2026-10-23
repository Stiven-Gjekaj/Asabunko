import AsaCore
import Foundation
import WidgetKit

extension AppModel {
    /// Writes the first books of Continue reading for the widget, with a small cover of each.
    /// The widget reloads only when the shelf changes.
    func updateShelf() {
        guard let folder = Shelf.folder else { return }
        let items = library.continueReading.prefix(4).map { book in
            Shelf.Item(id: book.id, title: book.title, place: book.place, progress: book.progress, cover: "\(book.id.uuidString).jpg")
        }
        let new = Shelf(items: Array(items))
        if shelf == nil { shelf = Shelf.load() }
        guard new != shelf else { return }
        shelf = new
        let covers = library.continueReading.prefix(4).map { (cover(of: $0), folder.appendingPathComponent("\($0.id.uuidString).jpg")) }
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // A widget has a small memory limit, so it gets small covers.
            for (source, target) in covers where !FileManager.default.fileExists(atPath: target.path) {
                try? Thumbnail.make(from: source, to: target, maxPixels: 600)
            }
            try? new.save()
            WidgetCenter.shared.reloadTimelines(ofKind: Shelf.widgetKind)
        }
    }
}

extension Book {
    /// "Page 3 of 20" for a comic or a PDF, or "Chapter 2 of 9" for a novel or a series.
    var place: String {
        format == .comic || format == .pdf ? String(localized: "Page \(page + 1) of \(pageCount)")
            : String(localized: "Chapter \(page + 1) of \(pageCount)")
    }
}
