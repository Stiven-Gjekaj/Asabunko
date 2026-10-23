import SwiftUI
import WidgetKit

@main
struct AsabunkoWidgets: WidgetBundle {
    var body: some Widget { ContinueReadingWidget() }
}

/// The books that the user reads now, with their covers. A tap on a book opens it in the app.
struct ContinueReadingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Shelf.widgetKind, provider: ShelfProvider()) { entry in
            ShelfView(entry: entry)
                .containerBackground(for: .widget) { Color("WidgetBackground") }
        }
        .configurationDisplayName("Continue reading")
        .description("The books that you read now.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ShelfEntry: TimelineEntry {
    let date: Date
    let shelf: Shelf
}

/// The app reloads the widget when the shelf changes, so the timeline has one entry and no time to reload.
struct ShelfProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShelfEntry {
        ShelfEntry(date: .now, shelf: Shelf(items: [Shelf.Item(id: UUID(), title: "A quiet morning", place: "Page 12 of 40", progress: 0.3)]))
    }

    func getSnapshot(in context: Context, completion: @escaping (ShelfEntry) -> Void) {
        let shelf = Shelf.load()
        completion(shelf.items.isEmpty ? placeholder(in: context) : ShelfEntry(date: .now, shelf: shelf))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShelfEntry>) -> Void) {
        completion(Timeline(entries: [ShelfEntry(date: .now, shelf: Shelf.load())], policy: .never))
    }
}

struct ShelfView: View {
    let entry: ShelfEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.shelf.items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "books.vertical").font(.title2).foregroundStyle(Color("WidgetAccent"))
                Text("Open a book in Asabunko to see it here.").font(.system(.footnote, design: .rounded))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else if family == .systemSmall, let item = entry.shelf.items.first {
            BookCell(item: item, large: true)
                .widgetURL(Shelf.link(to: item.id))
        } else {
            HStack(alignment: .top, spacing: 10) {
                ForEach(entry.shelf.items.prefix(3)) { item in
                    Link(destination: Shelf.link(to: item.id)) { BookCell(item: item, large: false) }
                }
                ForEach(0..<max(0, 3 - entry.shelf.items.count), id: \.self) { _ in Color.clear }
            }
        }
    }
}

private struct BookCell: View {
    let item: Shelf.Item
    let large: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The cover fills only the space that the text leaves. A filled image alone asks for its full size.
            Color.clear
                .overlay { cover }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Group {
                Text(item.title).font(.system(size: large ? 13 : 11, weight: .bold, design: .rounded)).lineLimit(1)
                if large { Text(item.place).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary).lineLimit(1) }
                ProgressView(value: item.progress).tint(Color("WidgetAccent"))
            }
            .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.place)")
    }

    @ViewBuilder
    private var cover: some View {
        if let name = item.cover, let file = Shelf.folder?.appendingPathComponent(name), let image = UIImage(contentsOfFile: file.path) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Color("WidgetAccent").opacity(0.25).overlay(Image(systemName: "book.closed").foregroundStyle(Color("WidgetAccent")))
        }
    }
}
