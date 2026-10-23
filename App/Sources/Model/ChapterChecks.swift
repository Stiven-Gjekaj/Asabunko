import AsaCore
import BackgroundTasks
import Network
import UIKit
import UserNotifications

/// The checks for new chapters in the background, and the notifications of their results.
/// iOS chooses the time of each check. The app asks for one hour after the last check at the earliest.
enum ChapterChecks {
    static let identifier = "io.github.stivengjekaj.asabunko.check"
    static let enabledKey = "checks.background"
    static let wifiKey = "downloads.wifiOnly"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Asks iOS for the next check, or removes the request when the user turned the checks off.
    static func schedule() {
        guard isOn else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        // The simulator has no background tasks, so a request can fail there.
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Asks the user for notifications. It gives false when the user refused them.
    static func askForNotifications() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// One notification for each book with new chapters. A tap on it opens the book.
    static func notify(_ found: [(book: Book, added: Int)]) async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        for (book, added) in found where added > 0 {
            let content = UNMutableNotificationContent()
            content.title = book.title
            content.body = added == 1 ? "1 new chapter" : "\(added) new chapters"
            content.threadIdentifier = book.id.uuidString
            content.userInfo = ["book": book.id.uuidString]
            try? await center.add(UNNotificationRequest(identifier: "chapters-\(book.id.uuidString)", content: content, trigger: nil))
        }
    }
}

/// The notifications of the app: a banner shows when the app is open, and a tap opens the book.
@MainActor final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationHandler()
    weak var app: AppModel?

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let text = response.notification.request.content.userInfo["book"] as? String, let id = UUID(uuidString: text) else { return }
        await MainActor.run { app?.openRequest = id }
    }
}

/// The kind of the network now, for the downloads that the user allows only on Wi-Fi.
final class NetworkKind: @unchecked Sendable {
    static let shared = NetworkKind()
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var wifi = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let wifi = path.status == .satisfied && !path.isExpensive && (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))
            self?.lock.withLock { self?.wifi = wifi }
        }
        monitor.start(queue: DispatchQueue(label: "asabunko.network-kind"))
    }

    var isWiFi: Bool { lock.withLock { wifi } }
}
