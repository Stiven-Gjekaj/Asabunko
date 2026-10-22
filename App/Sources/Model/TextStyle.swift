import SwiftUI
import UIKit

/// The look of the text of a novel, which the user chooses in the reader.
struct TextStyle: Equatable {
    enum Family: String, CaseIterable, Identifiable {
        case serif, sans, karla
        var id: String { rawValue }
        var name: String {
            switch self {
            case .serif: "Serif"
            case .sans: "Sans serif"
            case .karla: "Karla"
            }
        }
    }

    var family: Family
    var size: Double
    var lineHeight: Double
    var margin: Double
    var justify: Bool

    static let familyKey = "text.family", sizeKey = "text.size", lineKey = "text.lineHeight"
    static let marginKey = "text.margin", justifyKey = "text.justify"

    /// The CSS that goes over the CSS of the book. The colours come from the palette of the app.
    func css(dark: Bool) -> String {
        let background = dark ? "#17130F" : "#F6F0E4"
        let text = dark ? "#EDE3D6" : "#2B231C"
        let link = dark ? "#E34659" : "#B8303F"
        let font = switch family {
        case .serif: "'New York', ui-serif, 'Iowan Old Style', Georgia, serif"
        case .sans: "-apple-system, system-ui, sans-serif"
        case .karla: "'Karla', -apple-system, sans-serif"
        }
        return """
        \(family == .karla ? Self.karlaFace : "")
        html { background: \(background) !important; -webkit-text-size-adjust: none; }
        body {
          background: \(background) !important; color: \(text) !important;
          font-family: \(font) !important; font-size: \(Int(size))px !important;
          line-height: \(lineHeight) !important; text-align: \(justify ? "justify" : "start") !important;
          margin: 0 auto !important; padding: 116px \(Int(margin))px 132px !important; max-width: 40em !important;
          -webkit-hyphens: auto; hyphens: auto; overflow-wrap: break-word;
        }
        body * { color: inherit !important; background-color: transparent !important; font-family: inherit !important; line-height: inherit !important; }
        p { margin: 0 0 0.9em 0 !important; }
        h1, h2, h3 { line-height: 1.3 !important; text-align: start !important; }
        img, svg, video { max-width: 100% !important; height: auto !important; }
        a { color: \(link) !important; text-decoration: none !important; }
        """
    }

    /// Karla in base64. The web view runs in another process, so it does not see the fonts of the app.
    private static let karlaFace: String = {
        guard let url = Bundle.main.url(forResource: "Karla", withExtension: "ttf"),
              let data = try? Data(contentsOf: url) else { return "" }
        return "@font-face { font-family: 'Karla'; src: url(data:font/ttf;base64,\(data.base64EncodedString())) format('truetype'); font-weight: 200 800; }"
    }()
}
