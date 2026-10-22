import AppKit
import CoreGraphics
let src = NSImage(contentsOfFile: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "logo-full.png")!
var rect = CGRect(origin: .zero, size: src.size)
let cg = src.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
// The mark without the word: x 240...1000, y 90...850 from the top.
let mark = cg.cropping(to: CGRect(x: 240, y: 90, width: 760, height: 760))!
func write(_ image: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
func canvas(_ size: Int, background: CGColor?, scale: CGFloat) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    if let background { ctx.setFillColor(background); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size)) }
    let side = CGFloat(size) * scale
    ctx.draw(mark, in: CGRect(x: (CGFloat(size) - side) / 2, y: (CGFloat(size) - side) / 2, width: side, height: side))
    return ctx.makeImage()!
}
let bg = CGColor(srgbRed: 0x0E/255, green: 0x0B/255, blue: 0x0A/255, alpha: 1)
write(canvas(1024, background: bg, scale: 0.86), "icon-1024.png")
write(canvas(512, background: bg, scale: 0.86), "icon-512.png")
write(canvas(600, background: nil, scale: 1), "mark.png")
