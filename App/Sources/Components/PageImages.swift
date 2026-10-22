import CryptoKit
import ImageIO
import UIKit

/// Where the image of a page comes from: a file of the library, or the network.
enum PageSource: Hashable, @unchecked Sendable {
    case file(URL)
    case remote(URLRequest)

    var key: String {
        switch self {
        case let .file(url): url.path
        case let .remote(request): request.url?.absoluteString ?? ""
        }
    }
}

/// Loads the images of the pages at the size of the screen, and keeps the last ones.
/// A page of a comic can have more pixels than the screen. A smaller image keeps the memory low.
/// A page from the network stays in the caches folder, so that it does not load two times.
final class PageImages: @unchecked Sendable {
    static let shared = PageImages()

    private let cache = NSCache<NSString, UIImage>()
    private let folder = URL.cachesDirectory.appendingPathComponent("Pages", isDirectory: true)

    private init() {
        cache.countLimit = 24
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func image(_ url: URL, maxPixels: CGFloat) async -> UIImage? {
        await image(.file(url), maxPixels: maxPixels)
    }

    /// The image of the page with its long side at most `maxPixels`.
    func image(_ source: PageSource, maxPixels: CGFloat) async -> UIImage? {
        let key = "\(source.key)#\(Int(maxPixels))" as NSString
        if let image = cache.object(forKey: key) { return image }
        let image: UIImage?
        switch source {
        case let .file(url):
            image = await Task.detached(priority: .userInitiated) { Self.decode(url, maxPixels: maxPixels) }.value
        case let .remote(request):
            guard let file = await download(request) else { return nil }
            image = await Task.detached(priority: .userInitiated) { Self.decode(file, maxPixels: maxPixels) }.value
        }
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    /// Loads the next pages before the user turns to them.
    func prefetch(_ sources: [PageSource]) {
        for case let .remote(request) in sources {
            Task.detached(priority: .utility) { _ = await self.download(request) }
        }
    }

    private func download(_ request: URLRequest) async -> URL? {
        guard let url = request.url else { return nil }
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: file.path) { return file }
        guard let (data, response) = try? await Network.session.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              !data.isEmpty
        else { return nil }
        try? data.write(to: file, options: .atomic)
        return file
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

    /// Removes the pages from the network. The caches folder of iOS can also remove them.
    func clearDownloads() {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        cache.removeAllObjects()
    }

    /// The long side of the screen in pixels, two times for the zoom.
    @MainActor static var screenPixels: CGFloat {
        let screen = UIScreen.main
        return max(screen.bounds.width, screen.bounds.height) * screen.scale * 2
    }
}
