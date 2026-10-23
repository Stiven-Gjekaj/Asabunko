import UIKit

/// Counts the frames that come late, for the UI test of the scroll. It runs only with ASABUNKO_FRAME_METER=1.
/// The counts are the accessibility value of a small view with the identifier "frame-meter".
@MainActor final class FrameMeter: NSObject {
    static let shared = FrameMeter()

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var frames = 0
    private var late = 0
    private var lateTime: CFTimeInterval = 0
    private let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    /// Counts of events that a screen notes, such as a page that shows before its image.
    private var events: [String: Int] = [:]

    static var isOn: Bool { ProcessInfo.processInfo.environment["ASABUNKO_FRAME_METER"] == "1" }

    func start(in window: UIWindow) {
        guard link == nil else { return }
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "frame-meter"
        view.isUserInteractionEnabled = false
        window.addSubview(view)
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Counts one event. It does nothing when the meter is off.
    func note(_ name: String) {
        guard link != nil else { return }
        events[name, default: 0] += 1
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { last = link.timestamp }
        guard last > 0 else { return }
        frames += 1
        let gap = link.timestamp - last
        // A frame is late when the main thread misses more than half of the next frame.
        if gap > link.duration * 1.5 {
            late += 1
            lateTime += gap - link.duration
        }
        let counts = events.sorted { $0.key < $1.key }.map { " \($0.key)=\($0.value)" }.joined()
        view.accessibilityValue = "frames=\(frames) late=\(late) ms=\(Int(lateTime * 1000))" + counts
        view.window?.bringSubviewToFront(view)
    }
}
