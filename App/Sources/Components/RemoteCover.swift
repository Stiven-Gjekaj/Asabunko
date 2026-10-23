import SwiftUI

/// A cover from the network, with the shape of a paperback.
struct RemoteCover: View {
    let request: URLRequest?
    var title: String = ""
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Palette.surfaceHigh)
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Text(title)
                        .font(Karla.font(12, .bold))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner - 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner - 4, style: .continuous).stroke(Palette.outline, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            .task(id: request?.url) {
                guard let request else { return }
                image = await PageImages.shared.image(.remote(request), maxPixels: 600)
            }
            .accessibilityHidden(true)
    }
}

/// A grid of covers with titles, for a page of a catalog or of a source.
struct CoverGrid<Item: Identifiable, Destination: View>: View {
    let items: [Item]
    let title: (Item) -> String
    let subtitle: (Item) -> String?
    let cover: (Item) -> URLRequest?
    let destination: (Item) -> Destination

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 16, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 22) {
            ForEach(items) { item in
                NavigationLink { destination(item) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        RemoteCover(request: cover(item), title: title(item))
                        Text(title(item)).font(Karla.font(14, .bold)).lineLimit(2).multilineTextAlignment(.leading)
                        if let subtitle = subtitle(item) {
                            Text(subtitle).font(Karla.font(12)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
