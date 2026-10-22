import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ThumbnailError: Error { case cannotRead, cannotWrite }

/// Makes the small cover of a book from its first page.
public enum Thumbnail {
    /// Writes a JPEG with the long side at most `maxPixels`.
    public static func make(from image: URL, to output: URL, maxPixels: Int = 600) throws {
        guard let source = CGImageSourceCreateWithURL(image as CFURL, nil) else { throw ThumbnailError.cannotRead }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ThumbnailError.cannotRead
        }
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ThumbnailError.cannotWrite
        }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ThumbnailError.cannotWrite }
    }
}
