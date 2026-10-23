import AsaCore
import SwiftUI

/// The control of one filter or one setting of a source.
struct OptionRow: View {
    let option: SourceOption
    @Binding var value: OptionValue

    var body: some View {
        switch option.kind {
        case let .text(placeholder):
            TextField(option.title, text: Binding(get: { if case let .text(text) = value { text } else { "" } }, set: { value = .text($0) }),
                      prompt: placeholder.map { Text($0) })
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        case .toggle:
            Toggle(option.title, isOn: Binding(get: { if case let .toggle(on) = value { on } else { false } }, set: { value = .toggle($0) }))
        case let .select(choices):
            Picker(option.title, selection: Binding(get: { if case let .select(choice) = value { choice } else { choices.first?.value ?? "" } },
                                                    set: { value = .select($0) })) {
                ForEach(choices, id: \.self) { Text($0.label).tag($0.value) }
            }
        case let .sort(choices, canAscend):
            Picker(option.title, selection: Binding(get: { if case let .sort(index, _) = value { index } else { 0 } },
                                                    set: { value = .sort(index: $0, ascending: ascending) })) {
                ForEach(Array(choices.enumerated()), id: \.offset) { Text($1.label).tag($0) }
            }
            if canAscend {
                Toggle("Ascending", isOn: Binding(get: { ascending }, set: { new in
                    if case let .sort(index, _) = value { value = .sort(index: index, ascending: new) }
                }))
            }
        case let .multi(choices, excludable):
            NavigationLink {
                MultiChoiceList(title: option.title, choices: choices, excludable: excludable, value: $value)
            } label: {
                LabeledContent(option.title, value: summary(choices))
            }
        }
    }

    private var ascending: Bool { if case let .sort(_, up) = value { up } else { false } }

    private func summary(_ choices: [SourceOption.Choice]) -> String {
        guard case let .multi(included, excluded) = value else { return "" }
        let names = choices.filter { included.contains($0.value) }.map(\.label) + choices.filter { excluded.contains($0.value) }.map { "not " + $0.label }
        return names.isEmpty ? "Any" : names.joined(separator: ", ")
    }
}

/// The choices of a filter with many values. A tap includes a choice, then excludes it, then clears it.
private struct MultiChoiceList: View {
    let title: String
    let choices: [SourceOption.Choice]
    let excludable: Bool
    @Binding var value: OptionValue

    var body: some View {
        List(choices, id: \.self) { choice in
            Button { step(choice.value) } label: {
                HStack {
                    Text(choice.label).foregroundStyle(Palette.textPrimary)
                    Spacer()
                    switch state(choice.value) {
                    case 1: Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent).accessibilityLabel("Included")
                    case -1: Image(systemName: "minus.circle.fill").foregroundStyle(Palette.danger).accessibilityLabel("Excluded")
                    default: EmptyView()
                    }
                }
            }
        }
        .asaForm()
        .asaScreen()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var lists: (included: [String], excluded: [String]) {
        if case let .multi(included, excluded) = value { (included, excluded) } else { ([], []) }
    }

    private func state(_ choice: String) -> Int {
        lists.included.contains(choice) ? 1 : lists.excluded.contains(choice) ? -1 : 0
    }

    private func step(_ choice: String) {
        var (included, excluded) = lists
        switch state(choice) {
        case 1:
            included.removeAll { $0 == choice }
            if excludable { excluded.append(choice) }
        case -1:
            excluded.removeAll { $0 == choice }
        default:
            included.append(choice)
        }
        value = .multi(included: included, excluded: excluded)
    }
}

/// The filters of a source in a sheet. Apply gives the values to the list of the source.
struct FilterSheet: View {
    let options: [SourceOption]
    let applied: [String: OptionValue]
    let onApply: ([String: OptionValue]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: OptionValue] = [:]

    var body: some View {
        NavigationStack {
            Form {
                ForEach(options) { option in
                    OptionRow(option: option, value: Binding(get: { values[option.id] ?? option.initial }, set: { values[option.id] = $0 }))
                }
            }
            .asaForm()
            .asaScreen()
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { values = [:] }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(values)
                        dismiss()
                    }
                }
            }
            .onAppear { values = applied }
        }
    }
}

/// The settings of one source. A change goes to the source at once.
struct SourceSettingsScreen: View {
    let source: OnlineSource
    let name: String
    @State private var options: [SourceOption] = []
    @State private var values: [String: OptionValue] = [:]
    @State private var loaded = false

    var body: some View {
        Form {
            if loaded && options.isEmpty {
                Text("This source has no settings.").foregroundStyle(Palette.textSecondary)
            }
            ForEach(options) { option in
                OptionRow(option: option, value: Binding(get: { values[option.id] ?? option.initial }, set: { new in
                    values[option.id] = new
                    Task { await source.setSetting(option.id, new) }
                }))
            }
        }
        .asaForm()
        .asaScreen()
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            options = await source.settingOptions()
            values = await source.settingValues()
            loaded = true
        }
    }
}
