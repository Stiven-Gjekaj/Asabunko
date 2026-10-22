import SwiftUI

/// All pages in one column, as in a webtoon. The page at the top of the screen is the current page.
struct VerticalReader: View {
    let pages: [URL]
    @Binding var page: Int
    let onTap: () -> Void
    @State private var visible: Int?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(pages.indices, id: \.self) { index in
                    VerticalPage(url: pages[index], index: index).id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $visible, anchor: .top)
        .onTapGesture(perform: onTap)
        .onAppear { visible = page }
        .onChange(of: visible) { _, index in
            if let index, index != page { page = index }
        }
        .onChange(of: page) { _, index in
            if visible != index { visible = index }
        }
    }
}

private struct VerticalPage: View {
    let url: URL
    let index: Int
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(image.size, contentMode: .fit)
            } else {
                Rectangle().fill(Palette.surface).aspectRatio(2 / 3, contentMode: .fit)
                    .overlay(ProgressView())
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: url) { image = await PageImages.shared.image(url, maxPixels: PageImages.screenPixels / 2) }
        .accessibilityLabel("Page \(index + 1)")
    }
}
