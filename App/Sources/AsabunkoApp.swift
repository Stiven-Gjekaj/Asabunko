import SwiftUI
import UIKit
import UserNotifications

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
                .onChange(of: phase) { _, new in
                    if new != .active { app.flush() }
                    if new == .background { ChapterChecks.schedule() }
                }
                .background(FrameMeterHook())
                .task {
                    NotificationHandler.shared.app = app
                    UNUserNotificationCenter.current().delegate = NotificationHandler.shared
                    // A UI test runs the check of the background at the start, because the simulator has no background tasks.
                    if ProcessInfo.processInfo.environment["ASABUNKO_CHECK_NOW"] == "1" { await app.backgroundCheck() }
                }
        }
        .backgroundTask(.appRefresh(ChapterChecks.identifier)) { await app.backgroundCheck() }
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
