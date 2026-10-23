import CoreGraphics
import Foundation
import Testing
import WAT
@testable import AsaCore

/// A module in WAT that uses the canvas and the js imports as a source of aidoku-rs does.
private func drawingSource() throws -> Data {
    Data(try wat2wasm(#"""
    (module
      (import "canvas" "new_context" (func $context (param f32 f32) (result i32)))
      (import "canvas" "copy_image" (func $copy (param i32 i32 f32 f32 f32 f32 f32 f32 f32 f32) (result i32)))
      (import "canvas" "get_image" (func $image (param i32) (result i32)))
      (import "canvas" "get_image_width" (func $width (param i32) (result f32)))
      (import "js" "context_create" (func $js (result i32)))
      (import "js" "context_eval" (func $eval (param i32 i32 i32) (result i32)))
      (import "js" "context_eval_async" (func $evalAsync (param i32 i32 i32) (result i32)))
      (memory (export "memory") 1)
      (data (i32.const 16) "[1, 2, 3].map((n) => n * 2).join('-')")
      (data (i32.const 64) "Promise.resolve(40).then((n) => n + 2)")
      (func (export "start"))
      (func (export "free_result") (param i32))
      ;; Puts the right half of the image on the left, and the left half on the right.
      (func (export "swap") (param $img i32) (result i32)
        (local $ctx i32)
        (local.set $ctx (call $context (f32.const 2) (f32.const 1)))
        (drop (call $copy (local.get $ctx) (local.get $img) (f32.const 1) (f32.const 0) (f32.const 1) (f32.const 1) (f32.const 0) (f32.const 0) (f32.const 1) (f32.const 1)))
        (drop (call $copy (local.get $ctx) (local.get $img) (f32.const 0) (f32.const 0) (f32.const 1) (f32.const 1) (f32.const 1) (f32.const 0) (f32.const 1) (f32.const 1)))
        (call $image (local.get $ctx)))
      (func (export "width") (param $img i32) (result f32) (call $width (local.get $img)))
      (func (export "script") (result i32) (call $eval (call $js) (i32.const 16) (i32.const 37)))
      (func (export "promise") (result i32) (call $evalAsync (call $js) (i32.const 64) (i32.const 38))))
    """#))
}

/// The red, green, and blue values of each pixel of an image, in rows from the top.
private func pixels(_ image: CGImage) -> [[UInt8]] {
    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return stride(from: 0, to: data.count, by: 4).map { Array(data[$0..<($0 + 3)]) }
}

/// An image of two pixels: red on the left and blue on the right.
private func redBlue() -> CGImage {
    var data: [UInt8] = [255, 0, 0, 255, 0, 0, 255, 255]
    let context = CGContext(data: &data, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 8,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!
}

@Suite struct AidokuCanvasTests {
    private func host() throws -> AidokuHost {
        try AidokuHost(name: "draw", wasm: try drawingSource(), defaults: AidokuDefaults(file: nil, initial: [:]), fetcher: fixedFetcher([:]))
    }

    @Test func copiesThePartsOfAnImageToTheirPlaces() throws {
        let host = try host()
        #expect(pixels(redBlue()) == [[255, 0, 0], [0, 0, 255]])
        let drawn = try host.queue.sync { () -> CGImage? in
            let rid = host.add(.image(AidokuPicture(data: AidokuImages.png(redBlue())!)))
            let result = AidokuHost.i32(try host.invoke("swap", [.i32(UInt32(bitPattern: rid))])[0])
            #expect(AidokuHost.f32(try host.invoke("width", [.i32(UInt32(bitPattern: rid))])[0]) == 2)
            if case let .image(picture)? = host.item(result) { return picture.image }
            return nil
        }
        let image = try #require(drawn)
        #expect(pixels(image) == [[0, 0, 255], [255, 0, 0]], "The blue pixel is on the left now.")
        let png = try #require(AidokuImages.png(image))
        #expect(AidokuImages.decode(png).map(pixels) == [[0, 0, 255], [255, 0, 0]])
    }

    @Test func runsAScriptAndAPromiseInJavaScriptCore() throws {
        let host = try host()
        let texts = try host.queue.sync { () -> [String] in
            try ["script", "promise"].map { name in
                let rid = AidokuHost.i32(try host.invoke(name, [])[0])
                guard case let .bytes(data)? = host.item(rid) else { return "no result \(rid)" }
                return String(decoding: data, as: UTF8.self)
            }
        }
        #expect(texts == ["2-4-6", "42"])
    }

    @Test func readsAPathOfTheCanvasModule() throws {
        var w = PostcardWriter()
        w.unsigned(3)
        w.unsigned(0); w.f32(1); w.f32(2)
        w.unsigned(1); w.f32(5); w.f32(2)
        w.unsigned(5)
        let path = try #require(AidokuHost.path(w.data))
        #expect(path.boundingBox == CGRect(x: 1, y: 2, width: 4, height: 0))
        #expect(AidokuHost.path(Data([0x01, 0x09])) == nil, "An unknown step gives no path.")
    }
}
