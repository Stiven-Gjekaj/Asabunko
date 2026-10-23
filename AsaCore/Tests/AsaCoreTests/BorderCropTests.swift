import CoreGraphics
import Foundation
import Testing
@testable import AsaCore

@Suite struct BorderCropTests {
    /// A white page with a dark block, as a scan with white margins.
    private func page(width: Int, height: Int, block: CGRect, background: CGFloat = 1) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: background, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0.2, alpha: 1))
        // The rectangle of the test has its origin at the top left, as the image has.
        context.fill(CGRect(x: block.minX, y: CGFloat(height) - block.maxY, width: block.width, height: block.height))
        return context.makeImage()!
    }

    @Test func findsTheWhiteBordersOfAPage() {
        let image = page(width: 1000, height: 1500, block: CGRect(x: 100, y: 200, width: 700, height: 1000))
        let rect = BorderCrop.content(of: image)
        // The small copy has 1/5.86 of the pixels, so the edges are a few pixels from the block.
        #expect(abs(rect.minX - 100) < 15)
        #expect(abs(rect.minY - 200) < 15)
        #expect(abs(rect.maxX - 800) < 15)
        #expect(abs(rect.maxY - 1200) < 15)
    }

    @Test func findsABlackBorder() {
        // A black page with a light block, as a scan with black margins.
        let light = CGContext(data: nil, width: 800, height: 1200, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        light.setFillColor(CGColor(gray: 0, alpha: 1)); light.fill(CGRect(x: 0, y: 0, width: 800, height: 1200))
        // The block is near the top, so a crop with the rows in the wrong order fails. The context draws from the bottom.
        light.setFillColor(CGColor(gray: 0.9, alpha: 1)); light.fill(CGRect(x: 50, y: 1200 - 500, width: 700, height: 400))
        let rect = BorderCrop.content(of: light.makeImage()!)
        #expect(abs(rect.minX - 50) < 12 && abs(rect.maxX - 750) < 12)
        #expect(abs(rect.minY - 100) < 12 && abs(rect.maxY - 500) < 12)
    }

    @Test func keepsAPageWithNoBorderOrWithOneColor() {
        let full = page(width: 600, height: 900, block: CGRect(x: 0, y: 0, width: 600, height: 900))
        #expect(BorderCrop.content(of: full) == CGRect(x: 0, y: 0, width: 600, height: 900))
        let empty = page(width: 600, height: 900, block: .zero)
        #expect(BorderCrop.content(of: empty) == CGRect(x: 0, y: 0, width: 600, height: 900), "A white page has nothing to crop.")
        let nearly = page(width: 600, height: 900, block: CGRect(x: 2, y: 2, width: 596, height: 896))
        #expect(BorderCrop.content(of: nearly) == CGRect(x: 0, y: 0, width: 600, height: 900), "A thin border is no crop.")
    }
}
