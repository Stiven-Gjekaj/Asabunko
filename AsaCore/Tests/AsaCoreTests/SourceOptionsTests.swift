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
}
