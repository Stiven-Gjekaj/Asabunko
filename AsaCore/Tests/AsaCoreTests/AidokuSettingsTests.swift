import Foundation
import Testing
@testable import AsaCore

/// The settings form of an Aidoku source. The settings have the shapes of real sources: a sign-in with a link
/// that needs it, a page with a button, and an editable list.
@Suite struct AidokuSettingsTests {
    private let json = Data("""
    [
      {"type": "group", "title": "Account", "footer": "Sign in to read more.", "items": [
        {"type": "login", "key": "login", "title": "Sign in", "logoutTitle": "Sign out", "method": "basic", "useEmail": true},
        {"type": "link", "title": "Content warnings", "url": "https://site.test/settings", "external": true, "requires": "login"}
      ]},
      {"type": "group", "title": "Reading", "items": [
        {"type": "switch", "key": "hd", "title": "HD pages", "default": true},
        {"type": "select", "key": "server", "title": "Server", "values": ["a", "b"], "titles": ["Alpha", "Beta"], "default": "a"},
        {"type": "segment", "key": "quality", "title": "Quality", "options": ["Low", "High"], "default": 1},
        {"type": "stepper", "key": "count", "title": "Count", "minimumValue": 1, "maximumValue": 5, "default": 2},
        {"type": "text", "key": "token", "title": "Token", "secure": true, "requiresFalse": "hd"},
        {"type": "group", "items": [{"type": "multi-select", "key": "types", "title": "Types", "values": ["m", "w"], "titles": ["Manga", "Webtoon"]}]}
      ]},
      {"type": "page", "key": "filters", "title": "Content filters", "items": [
        {"type": "group", "items": [{"type": "editable-list", "key": "blocklist", "title": "Blocked tags", "placeholder": "Tag", "default": []}]},
        {"type": "button", "key": "reset", "title": "Reset", "confirmText": "Remove all filters?", "destructive": true}
      ]}
    ]
    """.utf8)

    private func settings(_ defaults: AidokuDefaults, languages: [String] = ["en"]) -> AidokuSettings {
        AidokuSettings(json: json, dynamic: nil, defaults: defaults, languages: languages, multiLanguage: false)
    }

    @Test func showsTheGroupsAsSectionsAndHidesTheRowsThatNeedASetting() throws {
        let form = try settings(AidokuDefaults(file: nil, initial: [:])).form("root")
        #expect(form.sections.map(\.header) == ["Account", "Reading", nil])
        #expect(form.sections[0].footer == "Sign in to read more.")
        // The link needs the sign-in, and the token needs HD off. The group in the group gives its row to the outer group.
        #expect(form.sections[0].rows.map(\.kind) == [.login])
        #expect(form.sections[1].rows.map(\.id) == ["hd", "server", "quality", "count", "types"])
        #expect(form.sections[1].rows.map(\.kind) == [.toggle, .link, .link, .stepper, .link])
        #expect(form.sections[1].rows[0].on == true, "A setting with no value has its default.")
        #expect(form.sections[1].rows[1].value == "Alpha")
        #expect(form.sections[1].rows[2].value == "High")
        #expect(form.sections[1].rows[3].number == 2)
        #expect(form.sections[1].rows[4].value == "None")
        #expect(form.sections[2].rows.map(\.form) == ["page:filters"])
        let login = try #require(form.sections[0].rows[0].login)
        #expect(login.method == "basic" && login.useEmail == true && !login.signedIn)
    }

    @Test func keepsEachValueInTheFormThatTheSourceReads() throws {
        let defaults = AidokuDefaults(file: nil, initial: [:])
        let settings = settings(defaults)
        try settings.act(form: "root", row: "hd", input: .toggle(false), token: nil, host: nil)
        #expect(defaults["hd"] == Data([0x00]))
        var form = try settings.form("root")
        #expect(form.sections[1].rows.map(\.id).contains("token"), "The token shows when HD is off.")
        #expect(form.sections[1].rows.first { $0.id == "token" }?.secure == true)

        try settings.act(form: "select:server", row: "b", input: .tap, token: nil, host: nil)
        #expect(defaults["server"] == Data([0x01, 0x62]))
        try settings.act(form: "select:quality", row: "0", input: .tap, token: nil, host: nil)
        #expect(defaults["quality"] == Data([0x00]), "A segment keeps the index of its choice.")
        try settings.act(form: "multi:types", row: "w", input: .tap, token: nil, host: nil)
        try settings.act(form: "multi:types", row: "m", input: .tap, token: nil, host: nil)
        #expect(defaults["types"] == Data([0x02, 0x01, 0x6D, 0x01, 0x77]), "The choices keep the order of the source.")
        #expect(try settings.form("multi:types").sections[0].rows.map(\.mark) == ["included", "included"])
        try settings.act(form: "root", row: "count", input: .number(9), token: nil, host: nil)
        #expect(defaults["count"] == Data(withUnsafeBytes(of: Float(5).bitPattern.littleEndian) { Array($0) }), "A stepper stays in its range.")
        form = try settings.form("root")
        #expect(form.sections[1].rows.map(\.value).compactMap { $0 }.contains("Beta"))
        #expect(form.sections[1].rows.first { $0.id == "types" }?.value == "Manga, Webtoon")
    }

    @Test func addsAndRemovesTheEntriesOfAList() throws {
        let defaults = AidokuDefaults(file: nil, initial: [:])
        let settings = settings(defaults)
        let page = try settings.form("page:filters")
        #expect(page.sections.flatMap(\.rows).map(\.kind) == [.link, .button])
        #expect(page.sections.flatMap(\.rows).last?.confirm == "Remove all filters?")
        try settings.act(form: "list:blocklist", row: "add", input: .text(" gore "), token: nil, host: nil)
        try settings.act(form: "list:blocklist", row: "add", input: .text("drama"), token: nil, host: nil)
        try settings.act(form: "list:blocklist", row: "entry:0", input: .tap, token: nil, host: nil)
        let list = try settings.form("list:blocklist")
        #expect(list.sections[0].rows.map(\.title) == ["drama"])
        #expect(list.sections[1].rows.map(\.kind) == [.input])
        #expect(try settings.form("page:filters").sections[0].rows[0].value == "1")
    }

    @Test func signsInAndOutWithTheKeysOfTheAidokuApp() throws {
        let defaults = AidokuDefaults(file: nil, initial: [:])
        let settings = settings(defaults)
        try settings.act(form: "root", row: "login", input: .login(username: "mina@site.test", password: "tea"), token: nil, host: nil)
        func text(_ key: String) -> String? { defaults[key].flatMap { var r = PostcardReader($0); return try? r.string() } }
        #expect(text("login") == "logged_in")
        #expect(text("login.username") == "mina@site.test")
        #expect(text("login.password") == "tea")
        var form = try settings.form("root")
        #expect(form.sections[0].rows.map(\.title) == ["Sign out", "Content warnings"], "The link shows after the sign-in.")
        #expect(form.sections[0].rows[0].login?.signedIn == true)
        #expect(form.sections[0].rows[0].subtitle == "mina@site.test")
        #expect(form.sections[0].rows[1].url == "https://site.test/settings")
        try settings.act(form: "root", row: "login", input: .logout, token: nil, host: nil)
        #expect(defaults["login"] == nil && defaults["login.password"] == nil)
        form = try settings.form("root")
        #expect(form.sections[0].rows.map(\.title) == ["Sign in"])
    }

    @Test func makesTheOAuthPageWithPKCEAndTheTokenRequest() throws {
        let oauth = Data("""
        [{"type": "login", "key": "login", "method": "oauth", "title": "Log in",
          "url": "https://auth.test/auth?client_id=neko&redirect_uri=neko://auth", "tokenUrl": "https://auth.test/token",
          "pkce": true, "callbackScheme": "neko"}]
        """.utf8)
        let defaults = AidokuDefaults(file: nil, initial: [:])
        let settings = AidokuSettings(json: oauth, dynamic: nil, defaults: defaults, languages: [], multiLanguage: false)
        let login = try #require(try settings.form("root").sections[0].rows[0].login)
        #expect(login.callbackScheme == "neko")
        let page = try #require(login.url.flatMap { URLComponents(string: $0) })
        let verifier = try #require(defaults["login.codeVerifier"].flatMap { var r = PostcardReader($0); return try? r.string() })
        #expect(page.queryItems?.first { $0.name == "code_challenge" }?.value == AidokuSettings.challenge(verifier))
        #expect(page.queryItems?.first { $0.name == "client_id" }?.value == "neko")
        // The verifier stays the same while the user has not signed in.
        #expect(try settings.form("root").sections[0].rows[0].login?.url == login.url)

        let request = try #require(settings.tokenRequest(row: "login", callback: URL(string: "neko://auth?code=abc")!))
        #expect(request.url?.absoluteString == "https://auth.test/token")
        #expect(request.httpMethod == "POST")
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        #expect(body == "client_id=neko&code=abc&code_verifier=\(verifier)&grant_type=authorization_code&redirect_uri=neko://auth")
        try settings.act(form: "root", row: "login", input: .callback(URL(string: "neko://auth?code=abc")!), token: #"{"access_token":"t"}"#, host: nil)
        #expect(defaults["login"].flatMap { var r = PostcardReader($0); return try? r.string() } == #"{"access_token":"t"}"#)
    }

    @Test func givesAChoiceOfTheLanguagesOfTheSource() throws {
        let defaults = AidokuDefaults(file: nil, initial: [:])
        let settings = settings(defaults, languages: ["en", "ja"])
        let form = try settings.form("root")
        #expect(form.sections[0].header == "Languages")
        try settings.act(form: "select:languages", row: "ja", input: .tap, token: nil, host: nil)
        #expect(defaults["languages"] == Data([0x01, 0x02, 0x6A, 0x61]), "A single language is a list of one.")
    }

    @Test func readsTheSettingsOfGetSettings() throws {
        // A group with a footer and one switch, in the postcard form of aidoku-rs.
        var w = PostcardWriter()
        w.unsigned(1)
        w.string("group"); w.string(""); w.string("Dynamic"); for _ in 0..<4 { w.u8(0) }
        w.unsigned(0); w.option("Made in code.") { $0.string($1) }
        w.unsigned(1)
        w.string("switch"); w.string("fast"); w.string("Fast mode"); for _ in 0..<4 { w.u8(0) }
        w.unsigned(3); w.option(nil as String?) { $0.string($1) }; w.option(nil as Bool?) { $0.bool($1) }; w.bool(true)
        let defaults = AidokuDefaults(file: nil, initial: [:])
        let settings = AidokuSettings(json: nil, dynamic: w.data, defaults: defaults, languages: [], multiLanguage: false)
        let form = try settings.form("root")
        #expect(form.sections.map(\.header) == ["Dynamic"])
        #expect(form.sections[0].footer == "Made in code.")
        #expect(form.sections[0].rows.map(\.on) == [true])
        #expect(defaults["fast"] == Data([0x01]), "A setting of get_settings gets its default.")
    }

    /// Opens the settings form of each package in ASABUNKO_AIX_DIR, such as a copy of Aidoku Community.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ASABUNKO_AIX_DIR"] != nil))
    func opensTheSettingsOfRealPackages() async throws {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ASABUNKO_AIX_DIR"]!)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "aix" }
        var opened = 0, rows = 0, forms = 0
        var kinds: [String: Int] = [:]
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let id = file.deletingPathExtension().lastPathComponent
            let info = SourceInfo(id: id, name: id, language: "en", version: "1", icon: nil, code: file, novels: false)
            guard let source = try? AidokuSource(info: info, package: file, settings: nil, fetcher: { _ in throw URLError(.notConnectedToInternet) }),
                  await source.hasSettingsForm() else { continue }
            let root = try #require(try await source.settingsForm(), "\(id)")
            opened += 1
            var queue = [root]
            while let form = queue.popLast() {
                forms += 1
                for row in form.sections.flatMap(\.rows) {
                    rows += 1
                    kinds["\(row.kind)", default: 0] += 1
                    if let child = row.form { queue.append(try await source.form(child)) }
                }
            }
        }
        print("SETTINGS", files.count, "packages,", opened, "with settings,", forms, "forms,", rows, "rows", kinds.sorted { $0.key < $1.key })
        #expect(kinds["unsupported"] == nil)
    }
}
