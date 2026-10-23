import AsaCore
import SwiftUI

/// The titles to find: a banner of popular titles, and rows of the popular and the latest titles of the sources.
struct DiscoverScreen: View {
    @Environment(AppModel.self) private var app

    private var feed: DiscoverFeed { app.discover }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if app.library.installed.isEmpty {
                        title.padding(.horizontal, gutter)
                        EmptyArt(
                            covers: [],
                            title: "Nothing to discover yet",
                            text: "Add a source list in Settings, Sources. Asabunko installs its sources, and their popular titles show here."
                        ) {
                            NavigationLink { SourcesHomeScreen() } label: { Text("Add sources") }
                                .buttonStyle(PillButtonStyle())
                        }
                    } else if feed.rows.isEmpty {
                        title.padding(.horizontal, gutter)
                        if feed.loading {
                            EmptyArt(covers: [], title: "Asking your sources", text: "The popular titles of each source come in a moment.")
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            EmptyArt(covers: [], title: "No source answered", text: "Pull down to ask again.")
                        }
                    } else {
                        DiscoverHero(items: feed.featured)
                        ForEach(feed.rows) { row in
                            CoverRow(
                                title: row.title, items: row.items,
                                name: \.hit.series.title, detail: { $0.sourceName }, cover: \.cover,
                                destination: { OnlineSeriesScreen(item: $0, app: app) }
                            )
                        }
                    }
                }
                .padding(.bottom, 32)
            }
            .ignoresSafeArea(edges: feed.rows.isEmpty ? [] : .top)
            .asaScreen()
            .toolbar(feed.rows.isEmpty ? .automatic : .hidden, for: .navigationBar)
            .refreshable { await feed.load(app, force: true) }
            .task(id: app.library.installed.map(\.id)) { await feed.load(app) }
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Something new to read").font(Karla.font(15, .medium)).foregroundStyle(Palette.textSecondary)
            Text("Discover").font(Karla.font(32, .bold, relativeTo: .largeTitle))
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension OnlineSeriesScreen {
    /// A title of Discover, from the source that gave it.
    init?(item: DiscoverFeed.Item, app: AppModel) {
        guard let installed = app.library.installed.first(where: { $0.id == item.hit.source }) else { return nil }
        self.init(installed: installed, series: item.hit.series)
    }
}

/// The large banner at the top of Discover, after the home banner of ZettaStream: the blurred cover as the art,
/// the cover, the facts, a short summary, and the buttons. The banner moves to the next title after a time.
struct DiscoverHero: View {
    let items: [DiscoverFeed.Featured]
    @Environment(AppModel.self) private var app
    @State private var index = 0

    private static let slideTime: Duration = .seconds(8)

    var body: some View {
        if !items.isEmpty {
            let shown = items[index % items.count]
            // The art is a background, so that its size does not change the size of the banner.
            VStack(spacing: 8) {
                Spacer(minLength: 0)
                content(shown).padding(.horizontal, gutter)
                dots.padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 430)
            .background {
                ZStack {
                    SplashArt(request: shown.item.cover)
                        .id(shown.id)
                        .transition(.opacity)
                    LinearGradient(
                        stops: [.init(color: Palette.background.opacity(0.1), location: 0), .init(color: Palette.background, location: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(swipe)
            .animation(.easeInOut(duration: 0.4), value: index)
            .onChange(of: items.map(\.id)) { index = 0 }
            .task(id: items.count) {
                guard items.count > 1 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.slideTime)
                    if Task.isCancelled { return }
                    index = (index + 1) % items.count
                }
            }
        }
    }

    private func content(_ shown: DiscoverFeed.Featured) -> some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Popular now".uppercased())
                    .font(Karla.font(12, .bold))
                    .kerning(1.5)
                    .foregroundStyle(Palette.accent)
                Text(shown.details?.series.title ?? shown.item.hit.series.title)
                    .font(Karla.font(26, .heavy, relativeTo: .title))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                let facts = [shown.item.sourceName] + (shown.details?.genres.prefix(3).map { $0 } ?? [])
                FlowLayout(spacing: 6, maxLines: 2) {
                    ForEach(facts, id: \.self) { FactChip(text: $0) }
                }
                if let summary = shown.details?.summary {
                    Text(summary)
                        .font(Karla.font(14))
                        .foregroundStyle(Palette.textPrimary.opacity(0.85))
                        .lineLimit(3)
                }
                HStack(spacing: 10) {
                    if let screen = OnlineSeriesScreen(item: shown.item, app: app) {
                        NavigationLink { screen } label: { Label("Read", systemImage: "book.fill") }
                            .buttonStyle(PillButtonStyle())
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RemoteCover(request: shown.item.cover, title: shown.item.hit.series.title)
                .frame(width: 112)
                .id(shown.id)
                .transition(.opacity)
        }
    }

    /// One mark for each title. The mark of the title on screen is long.
    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(items.indices, id: \.self) { i in
                let current = i == index % items.count
                Capsule()
                    .fill(current ? Palette.textPrimary : Palette.outline)
                    .frame(width: current ? 26 : 10, height: 4)
            }
        }
        .accessibilityHidden(true)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                guard items.count > 1, abs(value.translation.width) > abs(value.translation.height) else { return }
                index = (index + (value.translation.width < 0 ? 1 : items.count - 1)) % items.count
            }
    }
}
