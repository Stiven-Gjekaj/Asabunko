import SwiftUI
import UIKit

/// The part of the screen that the user taps, from the left edge to the right edge.
enum TapZone { case left, middle, right }

/// One page at a time, with a swipe or a tap at the edge. Each page zooms with a pinch or a double tap.
struct PagedReader: UIViewControllerRepresentable {
    let pages: [PageSource]
    let rightToLeft: Bool
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
        if let first = context.coordinator.controller(at: page) {
            controller.setViewControllers([first], direction: .forward, animated: false)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        let old = coordinator.parent
        coordinator.parent = self
        let shown = (controller.viewControllers?.first as? PageController)?.index
        guard shown != page || old.rightToLeft != rightToLeft, let next = coordinator.controller(at: page) else { return }
        let forward = page > (shown ?? 0)
        let direction: UIPageViewController.NavigationDirection = (forward != rightToLeft) ? .forward : .reverse
        controller.setViewControllers([next], direction: direction, animated: shown != nil && old.rightToLeft == rightToLeft)
    }

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PagedReader

        init(_ parent: PagedReader) { self.parent = parent }

        func controller(at index: Int) -> PageController? {
            guard parent.pages.indices.contains(index) else { return nil }
            PageImages.shared.prefetch(Array(parent.pages[min(index + 1, parent.pages.count)..<min(index + 4, parent.pages.count)]))
            return PageController(source: parent.pages[index], index: index) { [weak self] zone in
                self?.parent.onTap(zone)
            }
        }

        func pageViewController(_ controller: UIPageViewController, viewControllerBefore current: UIViewController) -> UIViewController? {
            guard let index = (current as? PageController)?.index else { return nil }
            return self.controller(at: parent.rightToLeft ? index + 1 : index - 1)
        }

        func pageViewController(_ controller: UIPageViewController, viewControllerAfter current: UIViewController) -> UIViewController? {
            guard let index = (current as? PageController)?.index else { return nil }
            return self.controller(at: parent.rightToLeft ? index - 1 : index + 1)
        }

        func pageViewController(
            _ controller: UIPageViewController, didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController], transitionCompleted completed: Bool
        ) {
            guard completed, let index = (controller.viewControllers?.first as? PageController)?.index else { return }
            parent.page = index
        }
    }
}

/// One page in a scroll view that zooms.
final class PageController: UIViewController, UIScrollViewDelegate {
    let index: Int
    private let source: PageSource
    private let onTap: (TapZone) -> Void
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()

    init(source: PageSource, index: Int, onTap: @escaping (TapZone) -> Void) {
        self.source = source
        self.index = index
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

        imageView.contentMode = .scaleAspectFit
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Page \(index + 1)"
        imageView.accessibilityValue = "Loading"
        scrollView.addSubview(imageView)

        let double = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        double.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(double)
        let single = UITapGestureRecognizer(target: self, action: #selector(singleTap(_:)))
        single.require(toFail: double)
        scrollView.addGestureRecognizer(single)

        let source = source
        Task { [weak self] in
            let image = await PageImages.shared.image(source, maxPixels: PageImages.screenPixels)
            self?.imageView.image = image
            self?.imageView.accessibilityValue = image == nil ? "Not loaded" : "Loaded"
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scrollView.setZoomScale(1, animated: false)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    @objc private func doubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1 {
            scrollView.setZoomScale(1, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let size = CGSize(width: scrollView.bounds.width / 2.5, height: scrollView.bounds.height / 2.5)
            scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }

    @objc private func singleTap(_ gesture: UITapGestureRecognizer) {
        let x = gesture.location(in: view).x / max(view.bounds.width, 1)
        onTap(x < 0.3 ? .left : x > 0.7 ? .right : .middle)
    }
}
