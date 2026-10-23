import SwiftUI
import UIKit

/// Keeps the screen on while a reader is open, when the setting is on.
private struct ReaderAwake: ViewModifier {
    @AppStorage(ReaderSettings.keepAwakeKey) private var keepAwake = true

    func body(content: Content) -> some View {
        content
            .onAppear { UIApplication.shared.isIdleTimerDisabled = keepAwake }
            .onChange(of: keepAwake) { _, on in UIApplication.shared.isIdleTimerDisabled = on }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

extension View {
    func readerAwake() -> some View { modifier(ReaderAwake()) }
}

enum ReaderSettings {
    static let keepAwakeKey = "reader.keepAwake"
}
