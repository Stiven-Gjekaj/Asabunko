import Foundation
import SwiftSoup
import WasmKit

/// The html module of aidoku-rs, with SwiftSoup, which has the behaviour of jsoup that the sources expect.
/// The error codes: -1 bad descriptor, -2 bad string, -3 bad HTML, -4 bad query, -5 no result, -6 SwiftSoup failed.
extension AidokuHost {
    private func element(_ rid: Int32) -> Element? {
        switch item(rid) {
        case let .document(document)?: document
        case let .element(element)?: element
        case let .node(node)?: node as? Element
        default: nil
        }
    }

    private func node(_ rid: Int32) -> Node? {
        switch item(rid) {
        case let .document(document)?: document
        case let .element(element)?: element
        case let .node(node)?: node
        default: nil
        }
    }

    private func elements(_ rid: Int32) -> Elements? {
        if case let .elements(list)? = item(rid) { return list }
        return nil
    }

    /// A new item for a node: an element when it is one.
    private func addNode(_ node: Node?) -> Int32 {
        guard let node else { return -5 }
        if let element = node as? Element { return add(.element(element)) }
        return add(.node(node))
    }

    /// A string result as a new item, or -5 when there is no value.
    private func text(_ value: String?) -> Int32 {
        guard let value else { return -5 }
        return addString(value)
    }

    func installHTML(define: (String, String, [ValueType], [ValueType], @escaping ([Value]) throws -> [Value]) -> Void) {
        let i32 = Self.i32
        let result = Self.result

        func one(_ name: String, _ body: @escaping (Int32) -> Int32) {
            define("html", name, [.i32], [.i32]) { a in result(body(i32(a[0]))) }
        }
        func withString(_ name: String, _ body: @escaping (Int32, String) -> Int32) {
            define("html", name, [.i32, .i32, .i32], [.i32]) { [unowned self] a in result(body(i32(a[0]), string(i32(a[1]), i32(a[2])))) }
        }

        define("html", "parse", [.i32, .i32, .i32, .i32], [.i32]) { [unowned self] a in
            guard let document = try? SwiftSoup.parse(string(i32(a[0]), i32(a[1])), string(i32(a[2]), i32(a[3]))) else { return result(-3) }
            return result(add(.document(document)))
        }
        define("html", "parse_fragment", [.i32, .i32, .i32, .i32], [.i32]) { [unowned self] a in
            guard let document = try? SwiftSoup.parseBodyFragment(string(i32(a[0]), i32(a[1])), string(i32(a[2]), i32(a[3]))) else { return result(-3) }
            return result(add(.document(document)))
        }
        define("html", "escape", [.i32, .i32], [.i32]) { [unowned self] a in
            result(addString(Entities.escape(string(i32(a[0]), i32(a[1])))))
        }
        define("html", "unescape", [.i32, .i32], [.i32]) { [unowned self] a in
            let raw = string(i32(a[0]), i32(a[1]))
            return result(addString((try? Entities.unescape(raw)) ?? raw))
        }

        withString("select") { [unowned self] rid, query in
            do {
                if let list = elements(rid) { return add(.elements(try list.select(query))) }
                guard let element = element(rid) else { return -1 }
                return add(.elements(try element.select(query)))
            } catch { return -4 }
        }
        withString("select_first") { [unowned self] rid, query in
            do {
                let found = try elements(rid).map { try $0.select(query).first() } ?? element(rid).map { try $0.select(query).first() }
                guard let first = found ?? nil else { return -5 }
                return add(.element(first))
            } catch { return -4 }
        }
        withString("attr") { [unowned self] rid, key in
            let name = key.hasPrefix("abs:") ? String(key.dropFirst(4)) : key
            let target = elements(rid).flatMap { list in list.array().first { $0.hasAttr(name) } } ?? element(rid)
            guard let target, target.hasAttr(name) else { return -5 }
            return text(try? target.attr(key))
        }
        withString("has_attr") { [unowned self] rid, key in
            let name = key.hasPrefix("abs:") ? String(key.dropFirst(4)) : key
            return (element(rid)?.hasAttr(name) ?? false) ? 1 : 0
        }
        withString("has_class") { [unowned self] rid, name in (element(rid)?.hasClass(name) ?? false) ? 1 : 0 }

        one("text") { [unowned self] rid in
            if let list = elements(rid) { return text(try? list.text()) }
            if let element = element(rid) { return text(try? element.text()) }
            if let node = node(rid) as? TextNode { return text(node.text()) }
            return -1
        }
        one("untrimmed_text") { [unowned self] rid in
            if let element = element(rid) { return text(try? element.text(trimAndNormaliseWhitespace: false)) }
            if let node = node(rid) as? TextNode { return text(node.getWholeText()) }
            return -1
        }
        one("own_text") { [unowned self] rid in text(element(rid)?.ownText()) }
        one("data") { [unowned self] rid in
            if let element = element(rid) { return text(element.data()) }
            if let node = node(rid) as? DataNode { return text(node.getWholeData()) }
            return -1
        }
        one("html") { [unowned self] rid in
            if let list = elements(rid) { return text(try? list.html()) }
            return text(try? element(rid)?.html())
        }
        one("outer_html") { [unowned self] rid in
            if let list = elements(rid) { return text(try? list.outerHtml()) }
            return text(try? node(rid)?.outerHtml())
        }
        one("id") { [unowned self] rid in text(element(rid)?.id()) }
        one("tag_name") { [unowned self] rid in text(element(rid)?.tagName()) }
        one("class_name") { [unowned self] rid in text(try? element(rid)?.className()) }
        one("base_uri") { [unowned self] rid in text(node(rid)?.getBaseUri()) }

        one("children") { [unowned self] rid in element(rid).map { add(.elements($0.children())) } ?? -1 }
        one("siblings") { [unowned self] rid in element(rid).map { add(.elements($0.siblingElements())) } ?? -1 }
        one("child_nodes") { [unowned self] rid in node(rid).map { add(.nodes($0.getChildNodes())) } ?? -1 }
        one("parent") { [unowned self] rid in addNode(node(rid)?.parent()) }
        one("next") { [unowned self] rid in
            if let element = element(rid) { return addNode(try? element.nextElementSibling()) }
            return addNode(node(rid)?.nextSibling())
        }
        one("previous") { [unowned self] rid in
            if let element = element(rid) { return addNode(try? element.previousElementSibling()) }
            return addNode(node(rid)?.previousSibling())
        }
        one("first") { [unowned self] rid in
            if case let .nodes(list)? = item(rid) { return addNode(list.first) }
            return addNode(elements(rid)?.first())
        }
        one("last") { [unowned self] rid in
            if case let .nodes(list)? = item(rid) { return addNode(list.last) }
            return addNode(elements(rid)?.last())
        }
        one("size") { [unowned self] rid in
            if case let .nodes(list)? = item(rid) { return Int32(list.count) }
            return elements(rid).map { Int32($0.size()) } ?? -1
        }
        define("html", "get", [.i32, .i32], [.i32]) { [unowned self] a in
            let rid = i32(a[0]), index = Int(i32(a[1]))
            if case let .nodes(list)? = item(rid) { return result(list.indices.contains(index) ? addNode(list[index]) : -5) }
            guard let list = elements(rid) else { return result(-1) }
            return result(index >= 0 && index < list.size() ? add(.element(list.get(index))) : -5)
        }
        one("kind") { [unowned self] rid in
            switch item(rid) {
            case .document?: 7
            case .elements?, .nodes?: 6
            case .element?: 5
            case let .node(node)?: node is TextNode ? 2 : node is DataNode ? 3 : node is Comment ? 4 : node is Element ? 5 : 1
            default: 0
            }
        }

        // The changes of the tree.
        withString("set_text") { [unowned self] rid, value in (try? element(rid)?.text(value)) != nil ? 0 : -6 }
        withString("set_html") { [unowned self] rid, value in (try? element(rid)?.html(value)) != nil ? 0 : -6 }
        withString("append") { [unowned self] rid, value in (try? element(rid)?.append(value)) != nil ? 0 : -6 }
        withString("prepend") { [unowned self] rid, value in (try? element(rid)?.prepend(value)) != nil ? 0 : -6 }
        withString("add_class") { [unowned self] rid, value in (try? element(rid)?.addClass(value)) != nil ? 0 : -6 }
        withString("remove_class") { [unowned self] rid, value in (try? element(rid)?.removeClass(value)) != nil ? 0 : -6 }
        withString("remove_attr") { [unowned self] rid, value in (try? element(rid)?.removeAttr(value)) != nil ? 0 : -6 }
        define("html", "set_attr", [.i32, .i32, .i32, .i32, .i32], [.i32]) { [unowned self] a in
            let done = try? element(i32(a[0]))?.attr(string(i32(a[1]), i32(a[2])), string(i32(a[3]), i32(a[4])))
            return result(done != nil ? 0 : -6)
        }
        one("remove") { [unowned self] rid in
            if let list = elements(rid) { return (try? list.remove()) != nil ? 0 : -6 }
            return (try? node(rid)?.remove()) != nil ? 0 : -6
        }
    }
}
