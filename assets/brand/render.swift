// Makes the app icon from the mark of the banner: the mark fills the width of the square, so that
// no bar shows at the sides. The few rows that go out at the top and the bottom are cut.
import AppKit
let src = NSImage(contentsOfFile: (CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "logo-full.png"))!
var rect = CGRect(origin: .zero, size: src.size)
let cg = src.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
// The solid pixels of the mark are at x 319...917 and y 164...801 from the top.
let mark = cg.cropping(to: CGRect(x: 319, y: 164, width: 599, height: 638))!
func render(_ size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let scale = CGFloat(size) / CGFloat(mark.width)
    let height = CGFloat(mark.height) * scale
    ctx.draw(mark, in: CGRect(x: 0, y: (CGFloat(size) - height) / 2, width: CGFloat(size), height: height))
    return ctx.makeImage()!
}
for (size, name) in [(1024, "icon-1024.png"), (512, "icon-512.png")] {
    try! NSBitmapImageRep(cgImage: render(size)).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: name))
}
