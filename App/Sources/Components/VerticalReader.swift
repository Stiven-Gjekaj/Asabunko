import SwiftUI

/// All pages in one column, as in a webtoon. The page at the top of the screen is the current page.
/// Each page has its height before its image comes, so the column does not jump when the images load.
struct VerticalReader: View {
    let pages: [PageSource]
    @Binding var page: Int
    let onTap: () -> Void
    @State private var visible: Int?
    /// The width of each page divided by its height, from the head of its file.
    @State private var shapes: [Int: CGFloat] = [:]
    /// The pages that load now before the user scrolls to them. The screen does not show it, so it is not state.
    @State private var ahead = Ahead()
    private static let count = 3

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(pages.indices, id: \.self) { index in
                    VerticalPage(source: pages[index], index: index, shape: shape(of: index)).id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $visible, anchor: .top)
        .onTapGesture(perform: onTap)
        .onAppear {
            visible = page
            loadAhead(from: page)
        }
        .onChange(of: visible) { _, index in
            if let index, index != page { page = index }
            if let index { loadAhead(from: index) }
        }
        .onChange(of: page) { _, index in
            if visible != index { visible = index }
        }
        .task(id: pages) { await readShapes() }
    }

    /// The shape of a page. A page that the app did not read yet takes the shape of the nearest page before it,
    /// because the strips of one chapter have almost one shape.
    private func shape(of index: Int) -> CGFloat {
        if let shape = shapes[index] { return shape }
        if let size = PageImages.shared.knownSize(pages[index]) { return size.width / size.height }
        for before in stride(from: index - 1, through: 0, by: -1) { if let shape = shapes[before] { return shape } }
        return shapes.values.first ?? 2 / 3
    }

    /// The sizes of the pages of the device come from the heads of their files, which is fast.
    /// The sizes go into the state one time, so the column renders again one time.
    private func readShapes() async {
        let found = await PageImages.shared.sizes(pages).mapValues { $0.width / $0.height }
        if !found.isEmpty { shapes.merge(found) { _, new in new } }
    }

    /// Loads the next pages, so that they are ready when the user scrolls to them.
    private func loadAhead(from index: Int) {
        let range = index..<min(index + Self.count + 1, pages.count)
        for next in range where ahead.running.insert(next).inserted {
            let source = pages[next]
            Task {
                // A page from the network has its size only after its download.
                if shapes[next] == nil, let size = await PageImages.shared.size(source) { shapes[next] = size.width / size.height }
                _ = await PageImages.shared.image(source, maxPixels: VerticalPage.pixels)
                ahead.running.remove(next)
            }
        }
    }
}

/// A box for the pages that load ahead.
private final class Ahead {
    var running: Set<Int> = []
}

private struct VerticalPage: View {
    let source: PageSource
    let index: Int
    let shape: CGFloat
    @State private var image: UIImage?

    init(source: PageSource, index: Int, shape: CGFloat) {
        self.source = source
        self.index = index
        self.shape = shape
        // A page that loaded ahead shows at once, with no placeholder.
        _image = State(initialValue: PageImages.shared.cached(source, maxPixels: Self.pixels))
    }

    @MainActor static var pixels: CGFloat { PageImages.screenPixels / 2 }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(image.size, contentMode: .fit)
            } else {
                Rectangle().fill(Palette.surface).aspectRatio(shape, contentMode: .fit)
                    .overlay(ProgressView())
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { if image == nil { FrameMeter.shared.note("placeholders") } }
        .task(id: source) {
            let shown = image == nil ? shape : nil
            image = await PageImages.shared.image(source, maxPixels: Self.pixels)
            // The page changes its height when the image has another shape than the placeholder.
            if let shown, let image, abs(image.size.width / image.size.height - shown) / shown > 0.05 { FrameMeter.shared.note("jumps") }
        }
        .accessibilityLabel("Page \(index + 1)")
    }
}
