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
    /// A UI test gives an empty folder in ASABUNKO_ROOT. The pages of that test go in it too.
    private let folder: URL = {
        if let path = ProcessInfo.processInfo.environment["ASABUNKO_ROOT"], !path.isEmpty {
            return URL(fileURLWithPath: path).appendingPathComponent("Caches/Pages", isDirectory: true)
        }
        return URL.cachesDirectory.appendingPathComponent("Pages", isDirectory: true)
    }()

    /// The downloads that run now, by the name of their file, so that a page that loads before the
    /// user turns to it does not download two times.
    private var running: [String: Task<URL?, Never>] = [:]
    /// The size in pixels of each page that the app read, so that a page can have its height before its image.
    private var sizes: [String: CGSize] = [:]
    private let lock = NSLock()

    private init() {
        cache.countLimit = 24
        // The cost of an image is the bytes of its pixels.
        cache.totalCostLimit = 200 * 1024 * 1024
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func image(_ url: URL, maxPixels: CGFloat) async -> UIImage? {
        await image(.file(url), maxPixels: maxPixels)
    }

    /// The image of the page if it is in the memory now, with no wait.
    func cached(_ source: PageSource, maxPixels: CGFloat) -> UIImage? {
        cache.object(forKey: "\(source.key)#\(Int(maxPixels))" as NSString)
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
            // A page of HTML in place of an image must not stay in the cache, so the next try loads it again.
            if image == nil { try? FileManager.default.removeItem(at: file) }
        }
        if let image, let cg = image.cgImage {
            cache.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height)
            lock.withLock { if sizes[source.key] == nil { sizes[source.key] = image.size } }
        }
        return image
    }

    /// The size of the page if the app read it before.
    func knownSize(_ source: PageSource) -> CGSize? { lock.withLock { sizes[source.key] } }

    /// The size of the page from the head of its file, with no decode. A page from the network downloads first.
    func size(_ source: PageSource) async -> CGSize? {
        if let size = knownSize(source) { return size }
        let file: URL
        switch source {
        case let .file(url): file = url
        case let .remote(request):
            guard let downloaded = await download(request) else { return nil }
            file = downloaded
        }
        let size = await Task.detached(priority: .userInitiated) { Self.pixelSize(file) }.value
        if let size { lock.withLock { sizes[source.key] = size } }
        return size
    }

    /// The sizes of many files of the device in one task.
    func sizes(_ sources: [PageSource]) async -> [Int: CGSize] {
        let files = sources.enumerated().compactMap { index, source -> (Int, String, URL)? in
            if case let .file(url) = source { (index, source.key, url) } else { nil }
        }
        let found = await Task.detached(priority: .userInitiated) {
            files.compactMap { index, key, url in Self.pixelSize(url).map { (index, key, $0) } }
        }.value
        lock.withLock { for (_, key, size) in found { sizes[key] = size } }
        return Dictionary(found.map { ($0.0, $0.2) }) { first, _ in first }
    }

    /// The width and the height of an image, after its orientation.
    private static func pixelSize(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat, let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0
        else { return nil }
        // The orientations 5 to 8 turn the image by a quarter.
        let turned = ((properties[kCGImagePropertyOrientation] as? Int) ?? 1) >= 5
        return turned ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
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
        let task: Task<URL?, Never> = lock.withLock {
            if let task = running[name] { return task }
            let task = Task { await self.fetch(request, to: file) }
            running[name] = task
            return task
        }
        let result = await task.value
        lock.withLock { running[name] = nil }
        return result
    }

    private func fetch(_ request: URLRequest, to file: URL) async -> URL? {
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
        // A strip of a webtoon is much taller than it is wide. Its width, not its long side, must fill the
        // screen, so the size limit grows with the shape of the strip.
        var limit = maxPixels
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? CGFloat, let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
           min(width, height) > 0 {
            let long = max(width, height), short = min(width, height)
            if long / short > 2.5 { limit = min(long, maxPixels / 2 * long / short) }
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(Int(limit), 1),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        // The first draw of an image in a form that the screen cannot use converts it on the main thread.
        // A tall strip takes some frames for that, so the conversion happens here, on the thread of the decode.
        let page = UIImage(cgImage: image)
        return page.preparingForDisplay() ?? page
    }

    /// The long side of the screen in pixels, two times for the zoom.
    @MainActor static var screenPixels: CGFloat {
        let screen = UIScreen.main
        return max(screen.bounds.width, screen.bounds.height) * screen.scale * 2
    }
}
