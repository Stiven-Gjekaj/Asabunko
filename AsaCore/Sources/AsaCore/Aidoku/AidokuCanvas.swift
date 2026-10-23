import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WasmKit

/// A canvas of the canvas module: a bitmap with its origin at the top left, as in aidoku-rs.
final class AidokuCanvas {
    let context: CGContext
    let width: Int
    let height: Int
    /// The transform of the source, after the flip of the bitmap.
    private var transform = CGAffineTransform.identity

    init?(width: Int, height: Int) {
        guard width > 0, height > 0, width <= 16_384, height <= 16_384,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        self.context = context
        self.width = width
        self.height = height
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
    }

    func setTransform(_ new: CGAffineTransform) {
        context.concatenate(transform.inverted())
        context.concatenate(new)
        transform = new
    }

    /// Draws an image into a rectangle. The bitmap is upside down, so the image turns again in the rectangle.
    func draw(_ image: CGImage, in rect: CGRect) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        context.restoreGState()
    }

    func image() -> CGImage? { context.makeImage() }
}

/// An image of the canvas module. An image from the network keeps its bytes, because a source can
/// read them with get_image_data and decrypt them. It turns into pixels only when the source draws it.
final class AidokuPicture {
    let data: Data?
    private var decoded: CGImage?
    private var tried = false

    init(data: Data) {
        self.data = data
    }

    init(image: CGImage) {
        data = nil
        decoded = image
        tried = true
    }

    var image: CGImage? {
        if !tried, let data {
            tried = true
            decoded = AidokuImages.decode(data)
        }
        return decoded
    }

    /// The bytes of a file of the image: the bytes from the network, or a PNG of the pixels.
    var fileData: Data? { data ?? image.flatMap(AidokuImages.png) }
}

enum AidokuImages {
    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

extension AidokuHost {
    /// A path of the canvas module: `Path { ops: Vec<PathOp> }` in postcard.
    static func path(_ data: Data) -> CGPath? {
        var r = PostcardReader(data)
        let path = CGMutablePath()
        func point() throws -> CGPoint { CGPoint(x: CGFloat(try r.f32()), y: CGFloat(try r.f32())) }
        do {
            let count = try r.unsigned()
            for _ in 0..<count {
                switch try r.varint() {
                case 0: path.move(to: try point())
                case 1: path.addLine(to: try point())
                case 2: let control = try point(); path.addQuadCurve(to: try point(), control: control)
                case 3:
                    let first = try point(), second = try point()
                    path.addCurve(to: try point(), control1: first, control2: second)
                case 4:
                    let center = try point()
                    let radius = CGFloat(try r.f32()), start = CGFloat(try r.f32()), sweep = CGFloat(try r.f32())
                    path.addArc(center: center, radius: radius, startAngle: start, endAngle: start + sweep, clockwise: sweep < 0)
                case 5: path.closeSubpath()
                default: return nil
                }
            }
        } catch {
            return nil
        }
        return path
    }

    func installCanvas(define: (String, String, [ValueType], [ValueType], @escaping ([Value]) throws -> [Value]) -> Void) {
        let i32 = Self.i32, f32 = Self.f32, result = Self.result
        func canvas(_ rid: Int32) -> AidokuCanvas? { if case let .canvas(canvas)? = item(rid) { return canvas }; return nil }
        func picture(_ rid: Int32) -> AidokuPicture? { if case let .image(picture)? = item(rid) { return picture }; return nil }
        func image(_ rid: Int32) -> CGImage? { picture(rid)?.image }
        func float(_ value: Value) -> CGFloat { CGFloat(f32(value)) }

        define("canvas", "new_context", [.f32, .f32], [.i32]) { [unowned self] a in
            guard let canvas = AidokuCanvas(width: Int(f32(a[0]).rounded()), height: Int(f32(a[1]).rounded())) else { return result(-6) }
            return result(add(.canvas(canvas)))
        }
        define("canvas", "set_transform", [.i32, .f32, .f32, .f32, .f32, .f32], [.i32]) { a in
            guard let canvas = canvas(i32(a[0])) else { return result(-1) }
            let transform = CGAffineTransform(translationX: float(a[1]), y: float(a[2])).scaledBy(x: float(a[3]), y: float(a[4])).rotated(by: float(a[5]))
            canvas.setTransform(transform)
            return result(0)
        }
        define("canvas", "copy_image", [.i32, .i32, .f32, .f32, .f32, .f32, .f32, .f32, .f32, .f32], [.i32]) { a in
            guard let canvas = canvas(i32(a[0])) else { return result(-1) }
            guard let picture = image(i32(a[1])) else { return result(-2) }
            let source = CGRect(x: float(a[2]), y: float(a[3]), width: float(a[4]), height: float(a[5])).integral
            guard let part = picture.cropping(to: source) else { return result(-4) }
            canvas.draw(part, in: CGRect(x: float(a[6]), y: float(a[7]), width: float(a[8]), height: float(a[9])))
            return result(0)
        }
        define("canvas", "draw_image", [.i32, .i32, .f32, .f32, .f32, .f32], [.i32]) { a in
            guard let canvas = canvas(i32(a[0])) else { return result(-1) }
            guard let picture = image(i32(a[1])) else { return result(-2) }
            canvas.draw(picture, in: CGRect(x: float(a[2]), y: float(a[3]), width: float(a[4]), height: float(a[5])))
            return result(0)
        }
        define("canvas", "fill", [.i32, .i32, .f32, .f32, .f32, .f32], [.i32]) { [unowned self] a in
            guard let canvas = canvas(i32(a[0])) else { return result(-1) }
            guard let path = Self.path(encodedBuffer(at: i32(a[1]))) else { return result(-7) }
            canvas.context.setFillColor(red: float(a[2]) / 255, green: float(a[3]) / 255, blue: float(a[4]) / 255, alpha: float(a[5]))
            canvas.context.addPath(path)
            canvas.context.fillPath()
            return result(0)
        }
        define("canvas", "stroke", [.i32, .i32, .i32], [.i32]) { [unowned self] a in
            guard let canvas = canvas(i32(a[0])) else { return result(-1) }
            guard let path = Self.path(encodedBuffer(at: i32(a[1]))) else { return result(-7) }
            var r = PostcardReader(encodedBuffer(at: i32(a[2])))
            do {
                let red = try r.f32(), green = try r.f32(), blue = try r.f32(), alpha = try r.f32()
                let width = try r.f32()
                let cap = try r.varint(), join = try r.varint()
                let miter = try r.f32()
                let dashes = try r.list { CGFloat(try $0.f32()) }
                let offset = try r.f32()
                let g = canvas.context
                g.setStrokeColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: CGFloat(alpha))
                g.setLineWidth(CGFloat(width))
                g.setLineCap([CGLineCap.round, .square, .butt][Int(min(cap, 2))])
                g.setLineJoin([CGLineJoin.round, .bevel, .miter][Int(min(join, 2))])
                g.setMiterLimit(CGFloat(miter))
                g.setLineDash(phase: CGFloat(offset), lengths: dashes)
                g.addPath(path)
                g.strokePath()
                return result(0)
            } catch {
                return result(-8)
            }
        }
        define("canvas", "draw_text", [.i32, .i32, .i32, .f32, .f32, .f32, .i32, .f32, .f32, .f32, .f32], [.i32]) { [unowned self] a in
            guard let canvas = canvas(i32(a[0])) else { return result(-1) }
            let text = string(i32(a[1]), i32(a[2]))
            let size = float(a[3])
            let base: CTFont
            if case let .font(font)? = item(i32(a[6])) { base = font } else { base = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil) }
            let font = CTFontCreateCopyWithAttributes(base, size, nil, nil)
            let color = CGColor(red: float(a[7]) / 255, green: float(a[8]) / 255, blue: float(a[9]) / 255, alpha: float(a[10]))
            let attributed = NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font, kCTForegroundColorAttributeName as NSAttributedString.Key: color])
            let line = CTLineCreateWithAttributedString(attributed)
            let g = canvas.context
            g.saveGState()
            // The text is upside down in the flipped bitmap, so it turns again at its base line.
            g.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            g.textPosition = CGPoint(x: float(a[4]), y: float(a[5]))
            CTLineDraw(line, g)
            g.restoreGState()
            return result(0)
        }
        define("canvas", "get_image", [.i32], [.i32]) { [unowned self] a in
            guard let canvas = canvas(i32(a[0])) else { return result(-1) }
            guard let picture = canvas.image() else { return result(-5) }
            return result(add(.image(AidokuPicture(image: picture))))
        }
        define("canvas", "new_font", [.i32, .i32], [.i32]) { [unowned self] a in
            let name = string(i32(a[0]), i32(a[1]))
            return result(add(.font(CTFontCreateWithName(name as CFString, 12, nil))))
        }
        define("canvas", "system_font", [.i32], [.i32]) { [unowned self] a in
            let weights: [CGFloat] = [-0.8, -0.6, -0.4, 0, 0.23, 0.3, 0.4, 0.56, 0.62]
            let weight = weights[Int(min(max(i32(a[0]), 0), 8))]
            let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontTraitsAttribute: [kCTFontWeightTrait: weight]] as CFDictionary)
            let base = CTFontCreateUIFontForLanguage(.system, 12, nil) ?? CTFontCreateWithName("Helvetica" as CFString, 12, nil)
            return result(add(.font(CTFontCreateCopyWithAttributes(base, 12, nil, descriptor))))
        }
        define("canvas", "load_font", [.i32, .i32], [.i32]) { [unowned self] a in
            let request = Request()
            request.url = URL(lenient: string(i32(a[0]), i32(a[1])))
            guard send(request) == 0, let body = request.response?.body,
                  let provider = CGDataProvider(data: body as CFData), let font = CGFont(provider)
            else { return result(-11) }
            return result(add(.font(CTFontCreateWithGraphicsFont(font, 12, nil, nil))))
        }
        define("canvas", "new_image", [.i32, .i32], [.i32]) { [unowned self] a in
            let data = read(i32(a[0]), i32(a[1]))
            guard !data.isEmpty else { return result(-3) }
            return result(add(.image(AidokuPicture(data: data))))
        }
        define("canvas", "get_image_data", [.i32], [.i32]) { [unowned self] a in
            guard let picture = picture(i32(a[0])) else { return result(-2) }
            guard let data = picture.fileData else { return result(-3) }
            return result(add(.bytes(data)))
        }
        define("canvas", "get_image_width", [.i32], [.f32]) { a in [.f32(Float(image(i32(a[0]))?.width ?? 0).bitPattern)] }
        define("canvas", "get_image_height", [.i32], [.f32]) { a in [.f32(Float(image(i32(a[0]))?.height ?? 0).bitPattern)] }
    }
}
