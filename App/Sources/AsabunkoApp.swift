import SwiftUI
import UIKit

@main
struct AsabunkoApp: App {
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var phase

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
                // The last place of the reader goes to the file before iOS can stop the app.
                .onChange(of: phase) { _, new in if new != .active { app.flush() } }
                .background(FrameMeterHook())
        }
    }
}

/// Starts the frame meter in the window of the app when a UI test asks for it.
private struct FrameMeterHook: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        if FrameMeter.isOn {
            Task { @MainActor in if let window = view.window { FrameMeter.shared.start(in: window) } }
        }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}
