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

    @Test func aSaveInstallsTheMissingEnglishSourcesAndRemovesTheSourcesThatLeftTheList() {
        let code = URL(string: "https://list.test/code")!
        func info(_ id: String, _ language: String, adult: Bool = false) -> SourceInfo {
            SourceInfo(id: id, name: id, language: language, version: "1", icon: nil, code: code, novels: false, adult: adult)
        }
        let available = [info("kept", "en"), info("new", "English"), info("all", "multi"), info("japanese", "ja"), info("adult", "en", adult: true)]
        // "gone" left the list. "japanese-old" is still in the list of an older save, so it stays.
        let available2 = available + [info("japanese-old", "ja")]
        let plan = SourceLanguages.sync(available2, installed: ["kept", "gone", "japanese-old"], adult: false)
        #expect(plan.install.map(\.id) == ["new", "all"], "Only the English sources and the sources of all languages go in, and not two times.")
        #expect(plan.remove == ["gone"])
        #expect(SourceLanguages.sync(available, installed: [], adult: true).install.map(\.id) == ["kept", "new", "all", "adult"])
        #expect(SourceLanguages.sync(available, installed: ["kept", "new", "all"], adult: false).install.isEmpty, "A save with no change installs nothing.")
    }
}
