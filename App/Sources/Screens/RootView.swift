import SwiftUI

/// The tabs of the app.
struct RootView: View {
    var body: some View {
        TabView {
            LibraryScreen().tabItem { Label("Library", systemImage: "books.vertical") }
            BrowseScreen().tabItem { Label("Browse", systemImage: "safari") }
            SettingsScreen().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Palette.accent)
    }
}
