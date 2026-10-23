import SwiftUI

/// The tabs of the app.
struct RootView: View {
    var body: some View {
        TabView {
            LibraryScreen().tabItem { Label("Library", systemImage: "books.vertical") }
            DiscoverScreen().tabItem { Label("Discover", systemImage: "sparkles") }
            SettingsScreen().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Palette.accent)
    }
}
