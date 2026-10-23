import CoreGraphics
import Foundation

/// Finds the plain borders of a scanned page, so that the reader can show the page with no white or black frame.
public enum BorderCrop {
    /// The part of the image with its content, in pixels of the image. A border is a band at an edge where each
    /// pixel is near the color of the corner. A page with no border, or a page that is all one color, gives the full image.
    /// - Parameter tolerance: how far a pixel can be from the color of the border, from 0 to 255.
    public static func content(of image: CGImage, tolerance: Int = 24) -> CGRect {
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        // A small copy is enough to find the borders, and it is fast.
        let scale = min(1, 256 / Double(max(image.width, image.height)))
        let width = max(Int(Double(image.width) * scale), 1), height = max(Int(Double(image.height) * scale), 1)
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return full }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The row 0 of the memory of a bitmap context is the top of the image.
        func value(_ x: Int, _ y: Int) -> Int { Int(pixels[y * width + x]) }
        let border = value(0, 0)
        func plainRow(_ y: Int) -> Bool { (0..<width).allSatisfy { abs(value($0, y) - border) <= tolerance } }
        func plainColumn(_ x: Int, _ rows: Range<Int>) -> Bool { rows.allSatisfy { abs(value(x, $0) - border) <= tolerance } }
        var top = 0, bottom = height
        while top < bottom, plainRow(top) { top += 1 }
        while bottom > top, plainRow(bottom - 1) { bottom -= 1 }
        guard bottom > top else { return full }
        var left = 0, right = width
        while left < right, plainColumn(left, top..<bottom) { left += 1 }
        while right > left, plainColumn(right - 1, top..<bottom) { right -= 1 }
        // A small margin stays, so that a line at the edge of the content does not touch the screen.
        let margin = 1
        left = max(left - margin, 0); top = max(top - margin, 0); right = min(right + margin, width); bottom = min(bottom + margin, height)
        let rect = CGRect(x: Double(left) / scale, y: Double(top) / scale, width: Double(right - left) / scale, height: Double(bottom - top) / scale)
            .integral.intersection(full)
        // A crop that keeps almost all of the page is no crop.
        return rect.width * rect.height > full.width * full.height * 0.97 ? full : rect
    }
}
