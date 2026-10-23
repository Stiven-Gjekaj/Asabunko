import SwiftUI

/// The tabs of the app.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            LibraryScreen().tabItem { Label("Library", systemImage: "books.vertical") }.tag(0)
            DiscoverScreen().tabItem { Label("Discover", systemImage: "sparkles") }.tag(1)
            SearchScreen().tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(2)
            SettingsScreen().tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
        }
        .tint(Palette.accent)
        // The Library opens a book that a notification asks for.
        .onChange(of: app.openRequest) { _, id in if id != nil { tab = 0 } }
        .overlay(alignment: .bottom) { BrowserCheckBanner() }
        // A fault of any tab shows here, so that it shows on each tab.
        .alert("Asabunko", isPresented: Binding(get: { app.fault != nil }, set: { if !$0 { app.fault = nil } })) {
            Button("OK") { app.fault = nil }
        } message: {
            Text(app.fault ?? "")
        }
    }
}
