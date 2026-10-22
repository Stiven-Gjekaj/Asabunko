import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Copies a PDF into the folder of a book as book.pdf, with a cover from its first page.
public enum PDFImporter {
    public static let fileName = "book.pdf"

    public enum Failure: Error, Equatable {
        case notPDF
        /// The PDF needs a password to open.
        case locked
        case noPages
    }

    public struct Info: Equatable, Sendable {
        public let title: String
        public let author: String?
        public let pageCount: Int
    }

    public static func importBook(from url: URL, into folder: URL) throws -> Info {
        guard let document = CGPDFDocument(url as CFURL) else { throw Failure.notPDF }
        if document.isEncrypted && !document.isUnlocked && !document.unlockWithPassword("") { throw Failure.locked }
        guard document.numberOfPages > 0 else { throw Failure.noPages }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(fileName))
        if let page = document.page(at: 1) {
            try? writeCover(of: page, to: folder.appendingPathComponent("cover.jpg"))
        }
        let info = document.info
        return Info(
            title: string(info, "Title")?.nonEmpty ?? ComicImporter.title(fromFileName: url.lastPathComponent),
            author: string(info, "Author")?.nonEmpty,
            pageCount: document.numberOfPages
        )
    }

    /// Draws the page on white, with the long side at most `maxPixels`.
    static func writeCover(of page: CGPDFPage, to url: URL, maxPixels: CGFloat = 600) throws {
        let box = page.getBoxRect(.cropBox)
        let scale = maxPixels / max(box.width, box.height)
        let width = Int((box.width * scale).rounded()), height = Int((box.height * scale).rounded())
        guard width > 0, height > 0, let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw ThumbnailError.cannotWrite }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.drawPDFPage(page)
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw ThumbnailError.cannotWrite }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ThumbnailError.cannotWrite }
    }

    private static func string(_ info: CGPDFDictionaryRef?, _ key: String) -> String? {
        guard let info else { return nil }
        var value: CGPDFStringRef?
        guard CGPDFDictionaryGetString(info, key, &value), let value, let text = CGPDFStringCopyTextString(value) else { return nil }
        return text as String
    }
}
