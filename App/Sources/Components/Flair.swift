import AsaCore
import SwiftUI

/// A soft glow of the accent colour behind the art of a screen.
struct AccentGlow: View {
    var body: some View {
        RadialGradient(colors: [Palette.accent.opacity(0.28), Palette.accent.opacity(0)], center: .center, startRadius: 4, endRadius: 190)
            .blur(radius: 18)
            .accessibilityHidden(true)
    }
}

/// Three covers in a fan, on a glow. An empty screen shows it, so that it does not look bare.
/// With no covers, it shows the mark of the app.
struct CoverFan: View {
    let covers: [URLRequest]
    @State private var lifted = false

    var body: some View {
        ZStack {
            AccentGlow().frame(width: 320, height: 240)
            if covers.count >= 3 {
                ForEach(0..<3, id: \.self) { index in
                    let turn = Double(index - 1)
                    RemoteCover(request: covers[index])
                        .frame(width: index == 1 ? 104 : 88)
                        .rotationEffect(.degrees(turn * (lifted ? 11 : 8)))
                        .offset(x: turn * (lifted ? 74 : 64), y: index == 1 ? (lifted ? -10 : -4) : 10)
                        .zIndex(index == 1 ? 1 : 0)
                }
            } else {
                Image("Mark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                    .shadow(color: Palette.accent.opacity(0.3), radius: 18, y: 6)
            }
        }
        .frame(height: 190)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { lifted = true }
        }
        .accessibilityHidden(true)
    }
}

/// The art and a message of an empty screen.
struct EmptyArt<Actions: View>: View {
    let covers: [URLRequest]
    let title: String
    let text: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 14) {
            CoverFan(covers: covers)
            Text(title)
                .font(Karla.font(22, .bold, relativeTo: .title2))
                .multilineTextAlignment(.center)
            Text(text)
                .font(Karla.font(15))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            actions().padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }
}

extension EmptyArt where Actions == EmptyView {
    init(covers: [URLRequest], title: String, text: String) {
        self.init(covers: covers, title: title, text: text) { EmptyView() }
    }
}

/// A small fact, such as a genre, in a thin frame. A dark fill keeps it easy to read on bright art.
struct FactChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Karla.font(13))
            .foregroundStyle(Palette.textPrimary.opacity(0.9))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Palette.background.opacity(0.6), in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(Palette.outline))
    }
}

/// Puts the views in lines from the left, and starts a new line when a view does not fit.
/// The views after `maxLines` lines do not show.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var maxLines = Int.max

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = place(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: frames.compactMap { $0?.maxX }.max() ?? 0, height: frames.compactMap { $0?.maxY }.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, place(subviews, width: bounds.width)) {
            if let frame {
                subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
            } else {
                subview.place(at: CGPoint(x: bounds.minX, y: bounds.minY), proposal: .zero)
            }
        }
    }

    private func place(_ subviews: Subviews, width: CGFloat) -> [CGRect?] {
        var frames: [CGRect?] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, line = 1
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                line += 1
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            if line > maxLines {
                frames.append(nil)
                continue
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: min(size.width, width), height: size.height)))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return frames
    }
}

/// An image from the network, filled and blurred, as the splash art behind a banner.
struct SplashArt: View {
    let request: URLRequest?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Palette.surface
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 26)
                    .saturation(1.2)
                    .opacity(0.75)
                    .transition(.opacity)
            }
        }
        .clipped()
        .task(id: request?.url) {
            guard let request else { return }
            let loaded = await PageImages.shared.image(.remote(request), maxPixels: 300)
            withAnimation(.easeOut(duration: 0.4)) { image = loaded }
        }
        .accessibilityHidden(true)
    }
}

/// A row of covers that scrolls from the side, with a title over it.
struct CoverRow<Item: Identifiable, Destination: View>: View {
    let title: String
    let items: [Item]
    let name: (Item) -> String
    let detail: (Item) -> String?
    let cover: (Item) -> URLRequest?
    let destination: (Item) -> Destination

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Karla.font(19, .bold))
                .padding(.horizontal, gutter)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        NavigationLink { destination(item) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                RemoteCover(request: cover(item), title: name(item))
                                Text(name(item)).font(Karla.font(14, .bold)).lineLimit(2).multilineTextAlignment(.leading)
                                if let detail = detail(item) {
                                    Text(detail).font(Karla.font(12)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                                }
                            }
                            .frame(width: 112, alignment: .leading)
                            .accessibilityElement(children: .combine)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, gutter)
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }
}
