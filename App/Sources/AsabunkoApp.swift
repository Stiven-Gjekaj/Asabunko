import SwiftUI
import UIKit

@main
struct AsabunkoApp: App {
    @State private var app = AppModel()

    init() {
        let title = [NSAttributedString.Key.font: Karla.uiFont(17, .bold)]
        UINavigationBar.appearance().titleTextAttributes = title
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: Karla.uiFont(32, .bold)]
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                // "Open in Asabunko" from Files or from another app gives a copy of the file.
                .onOpenURL { url in
                    Task { await app.importItems([url]) }
                }
        }
    }
}
