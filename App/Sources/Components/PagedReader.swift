import AsaCore
import SwiftUI
import UIKit

/// The part of the screen that the user taps, from the left edge to the right edge.
enum TapZone { case left, middle, right }

/// How a page fills the screen.
enum PageFit: String, CaseIterable, Sendable {
    case screen, width, height

    var name: String {
        switch self {
        case .screen: "Fit the screen"
        case .width: "Fit the width"
        case .height: "Fit the height"
        }
    }
}

/// What a tap at an edge of the page does.
enum TapZones: String, CaseIterable, Sendable {
    /// The left edge and the right edge turn back and forward, in the direction of the book.
    case edges
    /// A tap at each edge turns forward.
    case forward
    /// A tap at an edge only shows or hides the bars.
    case off

    var name: String {
        switch self {
        case .edges: "Left and right"
        case .forward: "Forward at each edge"
        case .off: "No turns"
        }
    }
}

/// The choices of the paged reader, which stay for all books.
struct PageLayout: Equatable {
    static let fitKey = "reader.fit", cropKey = "reader.crop", spreadsKey = "reader.spreads", shiftKey = "reader.shift", tapsKey = "reader.taps"
    var fit: PageFit = .screen
    var crop = false
    /// Two pages on a wide screen.
    var spreads = true
    /// The pairs move by one page.
    var shift = false
}

/// The spreads, or one page in each spread, or pairs of pages on a wide screen.
@MainActor func pageSpreads(_ pages: [PageSource], layout: PageLayout, wide: Bool) -> [[Int]] {
    guard wide && layout.spreads else { return pages.indices.map { [$0] } }
    return Spreads.make(count: pages.count, wide: { index in
        PageImages.shared.knownSize(pages[index]).map { $0.width > $0.height } ?? false
    }, shift: layout.shift)
}

/// One spread at a time, with a swipe or a tap at the edge. Each spread zooms with a pinch or a double tap.
struct PagedReader: UIViewControllerRepresentable {
    let pages: [PageSource]
    let spreads: [[Int]]
    let rightToLeft: Bool
    let layout: PageLayout
    @Binding var page: Int
    let onTap: (TapZone) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .scroll, navigationOrientation: .horizontal, options: [.interPageSpacing: 14]
        )
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.view.backgroundColor = .clear
        if let first = context.coordinator.controller(at: Spreads.index(of: page, in: spreads)) {
            controller.setViewControllers([first], direction: .forward, animated: false)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        let old = coordinator.parent
        coordinator.parent = self
        let target = Spreads.index(of: page, in: spreads)
        let shown = (controller.viewControllers?.first as? PageController)?.spread
        // A new layout, such as a turn of the device, shows the spread again with no animation.
        let changed = old.spreads != spreads || old.layout != layout || old.rightToLeft != rightToLeft
        guard shown != target || changed, let next = coordinator.controller(at: target) else { return }
        let forward = target > (shown ?? 0)
        let direction: UIPageViewController.NavigationDirection = (forward != rightToLeft) ? .forward : .reverse
        // A turn that comes while the last turn moves goes with no animation. Two animations at the same
        // time leave UIPageViewController in a state where the next turns do nothing.
        let animated = shown != nil && !changed && !coordinator.turning
        guard animated else {
            controller.setViewControllers([next], direction: direction, animated: false)
            return
        }
        coordinator.turning = true
        controller.setViewControllers([next], direction: direction, animated: true) { [weak controller] _ in
            // A second set with no animation clears the pages that UIPageViewController keeps from the animation.
            DispatchQueue.main.async {
                controller?.setViewControllers([next], direction: direction, animated: false)
                coordinator.turning = false
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PagedReader
        /// True while an animated turn moves.
        var turning = false

        init(_ parent: PagedReader) { self.parent = parent }

        func controller(at spread: Int) -> PageController? {
            guard parent.spreads.indices.contains(spread) else { return nil }
            let indices = parent.spreads[spread]
            let after = (indices.last ?? 0) + 1
            PageImages.shared.prefetch(Array(parent.pages[min(after, parent.pages.count)..<min(after + 3, parent.pages.count)]))
            return PageController(pages: indices.map { ($0, parent.pages[$0]) }, spread: spread, rightToLeft: parent.rightToLeft,
                                  layout: parent.layout) { [weak self] zone in self?.parent.onTap(zone) }
        }

        func pageViewController(_ controller: UIPageViewController, viewControllerBefore current: UIViewController) -> UIViewController? {
            guard let spread = (current as? PageController)?.spread else { return nil }
            return self.controller(at: parent.rightToLeft ? spread + 1 : spread - 1)
        }

        func pageViewController(_ controller: UIPageViewController, viewControllerAfter current: UIViewController) -> UIViewController? {
            guard let spread = (current as? PageController)?.spread else { return nil }
            return self.controller(at: parent.rightToLeft ? spread - 1 : spread + 1)
        }

        func pageViewController(
            _ controller: UIPageViewController, didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController], transitionCompleted completed: Bool
        ) {
            guard completed, let spread = (controller.viewControllers?.first as? PageController)?.spread else { return }
            parent.page = representative(of: spread, in: parent.spreads)
        }
    }
}

/// The page that stands for a spread: its first page, or its last page for the last spread, so that the book ends.
func representative(of spread: Int, in spreads: [[Int]]) -> Int {
    guard spreads.indices.contains(spread) else { return 0 }
    return spread == spreads.count - 1 ? (spreads[spread].last ?? 0) : (spreads[spread].first ?? 0)
}

/// One spread of one or two pages in a scroll view that zooms. The fit sets the size of the spread.
final class PageController: UIViewController, UIScrollViewDelegate {
    let spread: Int
    private let pages: [(index: Int, source: PageSource)]
    private let rightToLeft: Bool
    private let layout: PageLayout
    private let onTap: (TapZone) -> Void
    private let scrollView = UIScrollView()
    private let content = UIView()
    private var imageViews: [UIImageView] = []
    /// True after the first layout, which sets the start of the scroll.
    private var placed = false

    init(pages: [(Int, PageSource)], spread: Int, rightToLeft: Bool, layout: PageLayout, onTap: @escaping (TapZone) -> Void) {
        self.pages = pages.map { (index: $0.0, source: $0.1) }
        self.spread = spread
        self.rightToLeft = rightToLeft
        self.layout = layout
        self.onTap = onTap
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scrollView)
        scrollView.addSubview(content)

        // In a manga the first page of a pair is at the right.
        for page in rightToLeft ? pages.reversed() : pages {
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFit
            imageView.isAccessibilityElement = true
            imageView.accessibilityLabel = "Page \(page.index + 1)"
            imageView.accessibilityValue = "Loading"
            imageView.tag = page.index
            content.addSubview(imageView)
            imageViews.append(imageView)
        }

        let double = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        double.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(double)
        let single = UITapGestureRecognizer(target: self, action: #selector(singleTap(_:)))
        single.require(toFail: double)
        scrollView.addGestureRecognizer(single)

        let crop = layout.crop
        for (imageView, page) in zip(imageViews, rightToLeft ? pages.reversed() : pages) {
            let source = page.source
            Task { [weak self, weak imageView] in
                var image = await PageImages.shared.image(source, maxPixels: PageImages.screenPixels)
                if crop, let full = image { image = await Self.cropped(full) }
                imageView?.image = image
                imageView?.accessibilityValue = image == nil ? "Not loaded" : "Loaded"
                // The real shape of the page sets the start of the scroll again.
                self?.placed = false
                self?.view.setNeedsLayout()
            }
        }
    }

    /// The page with no plain border. The search runs on a small copy, away from the main thread.
    private static func cropped(_ image: UIImage) async -> UIImage {
        guard let cg = image.cgImage else { return image }
        let rect = await Task.detached(priority: .userInitiated) { BorderCrop.content(of: cg) }.value
        guard rect != CGRect(x: 0, y: 0, width: cg.width, height: cg.height), let part = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: part, scale: image.scale, orientation: image.imageOrientation)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard scrollView.zoomScale == 1 else { return }
        layoutSpread()
    }

    /// The pages side by side at one height. The fit gives the size of the spread in the screen.
    private func layoutSpread() {
        let bounds = scrollView.bounds.size
        guard bounds.width > 0, bounds.height > 0 else { return }
        // A page with no image yet has the shape of a page of a book.
        let shapes = imageViews.map { view -> CGFloat in
            guard let size = view.image?.size, size.height > 0 else { return 2 / 3 }
            return size.width / size.height
        }
        let shape = max(shapes.reduce(0, +), 0.1)
        let fitted: CGSize = switch layout.fit {
        case .screen:
            bounds.width / bounds.height > shape ? CGSize(width: bounds.height * shape, height: bounds.height) : CGSize(width: bounds.width, height: bounds.width / shape)
        case .width: CGSize(width: bounds.width, height: bounds.width / shape)
        case .height: CGSize(width: bounds.height * shape, height: bounds.height)
        }
        var x: CGFloat = 0
        for (view, part) in zip(imageViews, shapes) {
            let width = fitted.height * part
            view.frame = CGRect(x: x, y: 0, width: width, height: fitted.height)
            x += width
        }
        // The content stays at the origin, because the zoom scales it from there. Insets center a small spread.
        content.frame = CGRect(origin: .zero, size: fitted)
        scrollView.contentSize = fitted
        center()
        // A spread that is taller or wider than the screen starts at its top and at its first page.
        if !placed {
            placed = true
            let x = rightToLeft ? max(fitted.width - bounds.width, 0) : -scrollView.contentInset.left
            scrollView.contentOffset = CGPoint(x: x, y: -scrollView.contentInset.top)
        }
        // A side that fits the screen stays in the middle after a new size, such as a turn of the device.
        var offset = scrollView.contentOffset
        if fitted.width <= bounds.width { offset.x = -scrollView.contentInset.left }
        if fitted.height <= bounds.height { offset.y = -scrollView.contentInset.top }
        scrollView.contentOffset = offset
    }

    /// The insets that keep a spread that is smaller than the screen in the middle.
    private func center() {
        let bounds = scrollView.bounds.size, size = scrollView.contentSize
        scrollView.contentInset = UIEdgeInsets(top: max((bounds.height - size.height) / 2, 0), left: max((bounds.width - size.width) / 2, 0),
                                               bottom: 0, right: 0)
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { center() }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scrollView.setZoomScale(1, animated: false)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }

    @objc private func doubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1 {
            scrollView.setZoomScale(1, animated: true)
        } else {
            let point = gesture.location(in: content)
            let size = CGSize(width: scrollView.bounds.width / 2.5, height: scrollView.bounds.height / 2.5)
            scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }

    @objc private func singleTap(_ gesture: UITapGestureRecognizer) {
        let x = gesture.location(in: view).x / max(view.bounds.width, 1)
        onTap(x < 0.3 ? .left : x > 0.7 ? .right : .middle)
    }
}
