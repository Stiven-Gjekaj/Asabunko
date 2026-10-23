import SwiftUI

/// The tabs of the app.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        TabView {
            LibraryScreen().tabItem { Label("Library", systemImage: "books.vertical") }
            DiscoverScreen().tabItem { Label("Discover", systemImage: "sparkles") }
            SearchScreen().tabItem { Label("Search", systemImage: "magnifyingglass") }
            SettingsScreen().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Palette.accent)
        .overlay(alignment: .bottom) { BrowserCheckBanner() }
        // A fault of any tab shows here, so that it shows on each tab.
        .alert("Asabunko", isPresented: Binding(get: { app.fault != nil }, set: { if !$0 { app.fault = nil } })) {
            Button("OK") { app.fault = nil }
        } message: {
            Text(app.fault ?? "")
        }
    }
}
