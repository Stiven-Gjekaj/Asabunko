import UIKit
import XCTest

/// Reads a webtoon of tall strips in the vertical reader, and measures the hitches of fast scrolls.
/// The book is a CBZ that the test makes.
final class VerticalScrollTests: XCTestCase {
    private var app: XCUIApplication!
    private var book: URL!
    private let count = 40

    override func setUpWithError() throws {
        continueAfterFailure = false
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("asabunko-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        book = folder.appendingPathComponent("Tall_Tower.cbz")
        // Each strip has the size of a strip of a real webtoon: 800 pixels wide and 6000 pixels tall.
        try StoredZip.write((1...count).map { ("\($0).jpg", Self.strip($0)) }, to: book)
        app = XCUIApplication()
        app.launchEnvironment["ASABUNKO_ROOT"] = folder.appendingPathComponent("library").path
        app.launchEnvironment["ASABUNKO_FRAME_METER"] = "1"
        app.launch()
    }

    func testScrollsTallStripsFast() throws {
        XCTAssertTrue(app.staticTexts["Your shelf is empty"].waitForExistence(timeout: 10))
        app.open(book)
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Tall Tower'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 60))
        tile.tap()
        XCTAssertTrue(app.staticTexts["1 of \(count)"].waitForExistence(timeout: 15))
        app.buttons["Reading mode"].tap()
        app.buttons["Vertical scroll"].tap()
        sleep(2)

        // Twenty fast swipes down the book, faster than the strips load. The meter counts the frames that came late.
        let meter = app.otherElements["frame-meter"]
        XCTAssertTrue(meter.waitForExistence(timeout: 5))
        let before = Self.counts(meter)
        for _ in 0..<20 { app.swipeUp(velocity: .fast) }
        sleep(2)
        let after = Self.counts(meter)
        let late = after["late"]! - before["late"]!, ms = after["ms"]! - before["ms"]!, frames = after["frames"]! - before["frames"]!
        let placeholders = (after["placeholders"] ?? 0) - (before["placeholders"] ?? 0)
        let jumps = (after["jumps"] ?? 0) - (before["jumps"] ?? 0)
        let label = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'of \(count)'")).firstMatch
        print("VERTICAL frames \(frames), late \(late), late time \(ms) ms, placeholders \(placeholders), jumps \(jumps) (at the start: \(before["placeholders"] ?? 0), \(before["jumps"] ?? 0)); at",
              label.exists ? label.label : "no label")
        // The late time of the simulator changes with the load of the Mac, so the test does not check it.
        XCTAssertEqual(jumps, 0, "No page changes its height while the user scrolls.")
        XCTAssertLessThanOrEqual(placeholders, 2, "The next strips load before the user scrolls to them.")
    }

    private static func counts(_ meter: XCUIElement) -> [String: Int] {
        let text = meter.value as? String ?? ""
        return Dictionary(uniqueKeysWithValues: text.split(separator: " ").compactMap { part in
            let pair = part.split(separator: "=")
            return pair.count == 2 ? (String(pair[0]), Int(pair[1]) ?? 0) : nil
        })
    }

    private static func strip(_ number: Int) -> Data {
        let size = CGSize(width: 800, height: 6000)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            // Bands of colour give the JPEG real work to decode.
            for band in 0..<60 {
                UIColor(hue: CGFloat((number * 7 + band) % 30) / 30, saturation: 0.35, brightness: 0.9, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: CGFloat(band) * 100, width: size.width, height: 100))
            }
            let text = "\(number)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 300), .foregroundColor: UIColor.darkGray]
            for y in stride(from: 400, to: 6000, by: 1500) {
                text.draw(at: CGPoint(x: 250, y: y), withAttributes: attributes)
            }
        }
        return image.jpegData(compressionQuality: 0.8)!
    }
}
