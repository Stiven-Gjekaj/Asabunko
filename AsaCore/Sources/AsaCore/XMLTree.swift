import Foundation

/// A small tree of an XML document. The names are local names, with no prefix.
/// The keys of the attributes keep their prefix, such as "epub:type", and also have the local name.
public final class XMLElement: @unchecked Sendable {
    public let name: String
    public let attributes: [String: String]
    public internal(set) var children: [XMLElement] = []
    public internal(set) var text = ""
    public weak var parent: XMLElement?

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    public subscript(attribute: String) -> String? { attributes[attribute] }

    /// The first child with the name.
    public func child(_ name: String) -> XMLElement? { children.first { $0.name == name } }

    public func children(_ name: String) -> [XMLElement] { children.filter { $0.name == name } }

    /// Each element below this one with the name, in the order of the document.
    public func descendants(_ name: String) -> [XMLElement] {
        var found: [XMLElement] = []
        for child in children {
            if child.name == name { found.append(child) }
            found += child.descendants(name)
        }
        return found
    }

    /// The text of this element and of all elements below it, with the spaces made one.
    public var allText: String {
        var parts = [text]
        for child in children { parts.append(child.allText) }
        return parts.joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Parses a document. A document of XHTML can use the entities of HTML, such as &nbsp;,
    /// which XML does not know. The parser tries again with them changed into characters.
    public static func parse(_ data: Data) -> XMLElement? {
        if let root = Builder.parse(data) { return root }
        var text = TextDecoding.decode(data)
        for (entity, value) in htmlEntities { text = text.replacingOccurrences(of: entity, with: value) }
        return Builder.parse(Data(text.utf8))
    }

    static let htmlEntities = [
        "&nbsp;": "\u{00A0}", "&mdash;": "\u{2014}", "&ndash;": "\u{2013}", "&hellip;": "\u{2026}",
        "&lsquo;": "\u{2018}", "&rsquo;": "\u{2019}", "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}",
        "&copy;": "\u{00A9}", "&reg;": "\u{00AE}", "&trade;": "\u{2122}", "&middot;": "\u{00B7}",
        "&bull;": "\u{2022}", "&laquo;": "\u{00AB}", "&raquo;": "\u{00BB}", "&times;": "\u{00D7}",
    ]

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XMLElement?
        var current: XMLElement?

        static func parse(_ data: Data) -> XMLElement? {
            let builder = Builder()
            let parser = XMLParser(data: data)
            parser.shouldProcessNamespaces = true
            parser.shouldResolveExternalEntities = false
            parser.delegate = builder
            guard parser.parse() else { return nil }
            return builder.root
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            var all = attributes
            for (key, value) in attributes {
                if let colon = key.firstIndex(of: ":") { all[String(key[key.index(after: colon)...])] = all[String(key[key.index(after: colon)...])] ?? value }
            }
            let element = XMLElement(name: name, attributes: all)
            element.parent = current
            current?.children.append(element)
            if root == nil { root = element }
            current = element
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            current?.text += string
        }

        func parser(_ parser: XMLParser, foundCDATA data: Data) {
            current?.text += String(decoding: data, as: UTF8.self)
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            current = current?.parent
        }
    }
}
