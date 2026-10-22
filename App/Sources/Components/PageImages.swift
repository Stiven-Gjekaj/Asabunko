import ImageIO
import UIKit

/// Loads the images of the pages at the size of the screen, and keeps the last ones.
/// A page of a comic can have more pixels than the screen. A smaller image keeps the memory low.
final class PageImages: @unchecked Sendable {
    static let shared = PageImages()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 24
    }

    /// The image of `url` with its long side at most `maxPixels`.
    func image(_ url: URL, maxPixels: CGFloat) async -> UIImage? {
        let key = "\(url.path)#\(Int(maxPixels))" as NSString
        if let image = cache.object(forKey: key) { return image }
        let image = await Task.detached(priority: .userInitiated) {
            Self.decode(url, maxPixels: maxPixels)
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    private static func decode(_ url: URL, maxPixels: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(Int(maxPixels), 1),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    /// The long side of the screen in pixels, two times for the zoom.
    @MainActor static var screenPixels: CGFloat {
        let screen = UIScreen.main
        return max(screen.bounds.width, screen.bounds.height) * screen.scale * 2
    }
}
