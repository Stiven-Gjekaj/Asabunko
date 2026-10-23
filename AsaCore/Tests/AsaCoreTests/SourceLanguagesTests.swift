import Foundation
import Testing
@testable import AsaCore

@Suite struct SourceLanguagesTests {
    @Test func languagesMatchCodesNamesAndAll() {
        #expect(SourceLanguages.matches("en", preferred: ["en-US"]))
        #expect(SourceLanguages.matches("English", preferred: ["en-GB"]))
        #expect(SourceLanguages.matches("multi", preferred: ["ja"]))
        #expect(SourceLanguages.matches("", preferred: ["ja"]))
        #expect(!SourceLanguages.matches("fr", preferred: ["en-US"]))
        #expect(!SourceLanguages.matches("Français", preferred: ["en"]))
        #expect(SourceLanguages.matches("pt-BR", preferred: ["pt-PT"]))
    }

    @Test func pickLeavesOutAdultSourcesUntilAllowed() {
        let code = URL(string: "https://x.test/a.js")!
        let sources = [
            SourceInfo(id: "1", name: "One", language: "en", version: "1", icon: nil, code: code, novels: false),
            SourceInfo(id: "2", name: "Two", language: "en", version: "1", icon: nil, code: code, novels: false, adult: true),
            SourceInfo(id: "3", name: "Three", language: "de", version: "1", icon: nil, code: code, novels: false),
        ]
        #expect(SourceLanguages.pick(sources, preferred: ["en"], adult: false).map(\.id) == ["1"])
        #expect(SourceLanguages.pick(sources, preferred: ["en"], adult: true).map(\.id) == ["1", "2"])
    }
}
