import Foundation
import Testing
@testable import AsaCore

@Suite struct SourceOptionsTests {
    private let filters = Data("""
    [
      {"type": "text", "id": "author", "title": "Author", "placeholder": "Author name"},
      {"type": "sort", "name": "Sort", "canAscend": true, "options": ["Best", "Newest"], "default": {"index": 1, "ascending": false}},
      {"type": "select", "id": "status", "title": "Status", "options": ["All", "Ongoing"]},
      {"type": "multi-select", "title": "Type", "canExclude": true, "options": ["Manga", "Manhwa"], "ids": ["ja", "ko"]},
      {"type": "note", "text": "Only one genre."}
    ]
    """.utf8)

    @Test func readsTheFiltersOfAnAidokuPackage() {
        let list = AidokuOptions.filters(filters)
        #expect(list.map(\.id) == ["author", "sort", "status", "Type"], "A filter with no id takes its type or its title. A note does not show.")
        #expect(list[1].title == "Sort")
        #expect(list[1].initial == .sort(index: 1, ascending: false))
        #expect(list[2].initial == .select("All"))
        #expect(list[3].kind == .multi([.init(label: "Manga", value: "ja"), .init(label: "Manhwa", value: "ko")], excludable: true))
    }

    @Test func encodesTheFilterValuesInPostcard() {
        let list = AidokuOptions.filters(filters)
        let data = AidokuOptions.encode(["sort": .sort(index: 2, ascending: false), "Type": .multi(included: ["ko"], excluded: [])], filters: list)
        // Three values: the empty text of "author" does not go.
        var expected = Data([0x03])
        expected += Data([0x01, 0x04]) + Data("sort".utf8) + Data([0x04, 0x00])
        expected += Data([0x03, 0x06]) + Data("status".utf8) + Data([0x03]) + Data("All".utf8)
        expected += Data([0x04, 0x04]) + Data("Type".utf8) + Data([0x01, 0x02]) + Data("ko".utf8) + Data([0x00])
        #expect(data == expected)
    }

    @Test func settingsKeepTheirValuesInTheFormOfTheDefaults() throws {
        let json = Data("""
        [{"type": "group", "items": [
          {"type": "switch", "key": "hd", "title": "High quality", "default": true},
          {"type": "select", "key": "lang", "title": "Title", "values": ["", "en"], "titles": ["Primary", "English"], "default": "en"},
          {"type": "segment", "key": "size", "title": "Size", "options": ["Small", "Large"], "default": 1},
          {"type": "button", "key": "clear", "title": "Clear"}
        ]}]
        """.utf8)
        let list = AidokuOptions.settings(json)
        #expect(list.map(\.id) == ["hd", "lang", "size"])
        #expect(list[1].kind == .select([.init(label: "Primary", value: ""), .init(label: "English", value: "en")]))
        #expect(list[2].initial == .select("1"))
        for (setting, value) in zip(list, [OptionValue.toggle(false), .select(""), .select("0")]) {
            let bytes = AidokuOptions.encodeSetting(value, of: setting)
            #expect(AidokuOptions.decodeSetting(bytes, of: setting) == value)
        }
        // A segment is a number, as aidoku-rs reads it.
        #expect(AidokuOptions.encodeSetting(.select("1"), of: list[2]) == Data([0x02]))
    }

    private let plugin = """
    const { FilterTypes } = require('@libs/filterInputs');
    const { storage } = require('@libs/storage');
    exports.default = {
      id: 'opts', name: 'Options', site: 'https://opts.test/', version: '1.0.0',
      filters: {
        order: { label: 'Order', type: FilterTypes.Picker, value: 'new', options: [{ label: 'New', value: 'new' }, { label: 'Top', value: 'top' }] },
        done: { label: 'Completed', type: FilterTypes.Switch, value: false },
        tags: { label: 'Tags', type: FilterTypes.ExcludableCheckboxGroup, value: { include: [], exclude: [] }, options: [{ label: 'Sea', value: 'sea' }] },
      },
      pluginSettings: { mirror: { label: 'Mirror', value: 'a', type: 'Select', options: [{ label: 'A', value: 'a' }, { label: 'B', value: 'b' }] } },
      async popularNovels(page, { filters }) {
        const name = [filters.order.value, String(filters.done.value), filters.tags.value.include.join('+'), filters.tags.value.exclude.join('+'), storage.get('mirror') || 'none'].join('|');
        return [{ name, path: 'n/1' }];
      },
      async searchNovels(q) { return [{ name: 'search ' + q, path: 's/1' }]; },
      async parseNovel(path) { return { path, name: 'N', chapters: [] }; },
      async parseChapter() { return ''; },
    };
    """

    private func load(_ settings: URL?) async throws -> LNReaderPlugin {
        let info = SourceInfo(id: "opts", name: "Options", language: "English", version: "1.0.0", icon: nil, code: URL(string: "https://x.test/o.js")!, novels: true)
        return try await LNReaderPlugin(info: info, code: plugin, settings: settings, fetcher: { _ in throw URLError(.notConnectedToInternet) })
    }

    @Test func anLNReaderPluginGetsTheValuesOfTheFilters() async throws {
        let source = try await load(nil)
        let options = await source.filterOptions()
        #expect(options.map(\.id) == ["order", "done", "tags"])
        #expect(options[0].initial == .select("new"))
        #expect(options[2].kind == .multi([.init(label: "Sea", value: "sea")], excludable: true))
        let first = try await source.browse(page: 1, query: "", filters: [:])
        #expect(first.items.first?.title == "new|false|||none")
        let chosen = try await source.browse(page: 1, query: "", filters: ["order": .select("top"), "done": .toggle(true), "tags": .multi(included: [], excluded: ["sea"])])
        #expect(chosen.items.first?.title == "top|true||sea|none")
        #expect(try await source.browse(page: 1, query: "tide", filters: ["done": .toggle(true)]).items.first?.title == "search tide")
    }

    @Test func aSettingOfAnLNReaderPluginStaysInItsFile() async throws {
        let file = try temporaryFolder().appendingPathComponent("opts.settings.json")
        let source = try await load(file)
        #expect(await source.settingOptions().map(\.id) == ["mirror"])
        #expect(await source.settingValues()["mirror"] == .select("a"))
        await source.setSetting("mirror", .select("b"))
        #expect(try await source.browse(page: 1, query: "", filters: [:]).items.first?.title.hasSuffix("|b") == true)
        // A new load of the plugin reads the saved value.
        let again = try await load(file)
        #expect(await again.settingValues()["mirror"] == .select("b"))
    }
}
