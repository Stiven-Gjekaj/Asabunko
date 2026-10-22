// Makes the app icon and the mark from the square logo, with a softer red.
// Usage: swift render.swift logo-square.png
import AppKit
import CoreGraphics

let input = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "logo-square.png"
let source = NSImage(contentsOfFile: input)!
var rect = CGRect(origin: .zero, size: source.size)
let image = source.cgImage(forProposedRect: &rect, context: nil, hints: nil)!

/// The red of the logo is #F82838. The owner asked for a softer red, so each red pixel
/// loses 18 percent of its saturation and 10 percent of its brightness. Cream and black do not change.
func soften(_ image: CGImage, size: Int) -> CGImage {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    let pixels = context.data!.bindMemory(to: UInt8.self, capacity: size * size * 4)
    for i in stride(from: 0, to: size * size * 4, by: 4) {
        let r = CGFloat(pixels[i]) / 255, g = CGFloat(pixels[i + 1]) / 255, b = CGFloat(pixels[i + 2]) / 255
        let maxC = max(r, g, b), minC = min(r, g, b)
        guard maxC == r, maxC > 0.1, maxC - minC > 0.15 else { continue }
        let s = (maxC - minC) / maxC
        let newV = maxC * 0.90, newS = s * 0.82
        let newMin = newV * (1 - newS)
        // Keep the hue: each channel keeps its place between the lowest and the highest.
        func map(_ c: CGFloat) -> UInt8 { UInt8(max(0, min(255, (newMin + (c - minC) / (maxC - minC) * (newV - newMin)) * 255))) }
        pixels[i] = map(r); pixels[i + 1] = map(g); pixels[i + 2] = map(b)
    }
    return context.makeImage()!
}

func write(_ image: CGImage, _ path: String) {
    try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

write(soften(image, size: 1024), "icon-1024.png")
write(soften(image, size: 512), "icon-512.png")
write(soften(image, size: 600), "mark.png")
