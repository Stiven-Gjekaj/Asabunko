import Foundation
import Testing
@testable import AsaCore

@Suite struct SourceListTests {
    @Test func readsOneSourceOnEachLineWithItsKind() {
        let text = """
        # My sources
        https://komga.local:25600/opds/v1.2/catalog

        https://raw.githubusercontent.com/LNReader/lnreader-plugins/plugins/v3.0.0/.dist/plugins.min.json
        https://aidoku-community.github.io/sources/index.min.json
        https://inkdex.github.io/extensions/0.9/stable/versioning.json
        http://192.168.1.20:4567
        not a url
        https://komga.local:25600/opds/v1.2/catalog
        """
        let lines = SourceList.parse(text)
        #expect(lines.map(\.link.kind) == [.opds, .lnreader, .aidoku, .paperback, .suwayomi])
    }

    @Test func takesTheUserAndThePasswordOutOfTheURL() throws {
        let line = try #require(SourceList.parse("https://asa:sun%40rise@kavita.local/api/opds/key").first)
        #expect(line.link.url == URL(string: "https://kavita.local/api/opds/key"))
        #expect(line.link.username == "asa")
        #expect(line.password == "sun@rise")
        #expect(line.link.shortAddress == "https://kavita.local/...")
    }

    @Test func writesTheUserButNotThePassword() {
        let links = SourceList.parse("https://asa:secret@komga.local/opds\nhttps://example.org/opds").map(\.link)
        #expect(SourceList.format(links) == "https://asa@komga.local/opds\nhttps://example.org/opds")
    }

    @Test func keepsTheIdentityOfASourceThatStays() throws {
        let old = SourceLink(url: URL(string: "https://komga.local/opds")!, username: "asa", kind: .opds, name: "Home")
        let line = try #require(SourceList.parse("https://asa@komga.local/opds", existing: [old]).first)
        #expect(line.link == old)
        #expect(line.password == nil)
    }

    @Test func detectsTheKindFromTheContent() {
        #expect(SourceKind.detect(Data(#"<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom"></feed>"#.utf8)) == .opds)
        #expect(SourceKind.detect(Data(#"[{"id":"a","name":"A","site":"https://a","url":"https://x/a.js"}]"#.utf8)) == .lnreader)
        #expect(SourceKind.detect(Data(#"{"name":"List","sources":[{"id":"a","downloadURL":"sources/a.aix"}]}"#.utf8)) == .aidoku)
        #expect(SourceKind.detect(Data(#"{"buildTime":"x","builtWith":{},"sources":[]}"#.utf8)) == .paperback)
        #expect(SourceKind.detect(Data("<html></html>".utf8)) == nil)
    }
}
