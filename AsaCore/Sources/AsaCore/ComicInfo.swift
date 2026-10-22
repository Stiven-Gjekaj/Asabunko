import Foundation

/// The metadata of a comic from its ComicInfo.xml, the format of ComicRack.
public struct ComicInfo: Sendable, Equatable {
    public var title: String?
    public var series: String?
    public var number: String?
    public var volume: String?
    public var writer: String?
    public var summary: String?
    public var languageISO: String?
    /// "Yes", "YesAndRightToLeft", "No", or "Unknown".
    public var manga: String?

    public init() {}

    /// The direction that the comic asks for, or nil when it does not ask.
    public var readingMode: ReadingMode? {
        guard let manga else { return nil }
        return manga.caseInsensitiveCompare("YesAndRightToLeft") == .orderedSame ? .rightToLeft : nil
    }

    /// "Series 12: Title", "Series 12", or "Title".
    public var displayTitle: String? {
        let title = title?.nonEmpty
        guard let series = series?.nonEmpty else { return title }
        let numbered = [series, number?.nonEmpty].compactMap { $0 }.joined(separator: " ")
        guard let title, title.caseInsensitiveCompare(series) != .orderedSame else { return numbered }
        return "\(numbered): \(title)"
    }

    /// Reads ComicInfo.xml. It returns nil when the data is not XML.
    public static func parse(_ data: Data) -> ComicInfo? {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else { return nil }
        return reader.info
    }

    private final class Reader: NSObject, XMLParserDelegate {
        var info = ComicInfo()
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            text = ""
            guard !value.isEmpty else { return }
            switch name {
            case "Title": info.title = value
            case "Series": info.series = value
            case "Number": info.number = value
            case "Volume": info.volume = value
            case "Writer": info.writer = value
            case "Summary": info.summary = value
            case "LanguageISO": info.languageISO = value
            case "Manga": info.manga = value
            default: break
            }
        }
    }
}

extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
