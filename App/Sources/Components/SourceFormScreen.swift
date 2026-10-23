import AsaCore
import SwiftUI

/// A settings form of a source. With no `id`, the screen opens the root form of the source.
/// The source gives the form again after each action, so the rows can change.
struct SourceFormScreen: View {
    let source: OnlineSource
    let title: String
    var id: String?
    @Environment(\.dismiss) private var dismiss
    @State private var form: SourceForm?
    @State private var busy = false
    @State private var fault: String?

    var body: some View {
        Form {
            if let fault {
                Text(fault).foregroundStyle(Palette.danger)
            }
            if let form {
                ForEach(form.sections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            FormRow(source: source, row: row) { input in act(row, input) }
                        }
                    } header: {
                        if let header = section.header { Text(header) }
                    } footer: {
                        if let footer = section.footer { Text(footer) }
                    }
                }
            } else if fault == nil {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .disabled(busy)
        .asaForm()
        .asaScreen()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if form?.submit == true {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        // The task runs again when a child form closes, so the values of this form are new.
        .task { await load() }
    }

    private func load() async {
        do {
            if let form {
                self.form = try await source.form(form.id)
            } else if let id {
                form = try await source.form(id)
            } else {
                form = try await source.settingsForm()
                if form == nil { fault = "This source has no settings." }
            }
        } catch {
            fault = error.localizedDescription
        }
    }

    private func act(_ row: SourceForm.Row, _ input: FormInput) {
        guard let form else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                self.form = try await source.formAction(form.id, row: row.id, input: input)
                fault = nil
            } catch {
                fault = error.localizedDescription
            }
        }
    }

    private func save() {
        guard let form else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await source.submitForm(form.id)
                dismiss()
            } catch {
                fault = error.localizedDescription
            }
        }
    }
}

/// One row of a settings form.
private struct FormRow: View {
    let source: OnlineSource
    let row: SourceForm.Row
    let act: (FormInput) -> Void

    var body: some View {
        switch row.kind {
        case .label:
            if row.selectable == true {
                Button { act(.tap) } label: { label }
                    .accessibilityAddTraits(row.mark == "included" ? .isSelected : [])
            } else {
                label
            }
        case .input:
            InputRow(row: row) { act(.text($0)) }
        case .toggle:
            Toggle(isOn: Binding(get: { row.on ?? false }, set: { act(.toggle($0)) })) { titles }
        case .button:
            Button(row.title) { act(.tap) }
        case .link:
            NavigationLink { SourceFormScreen(source: source, title: row.title, id: row.form) } label: { label }
        case .unsupported:
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).foregroundStyle(Palette.textSecondary)
                Text("Asabunko cannot do this action.").font(.caption).foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title).foregroundStyle(Palette.textPrimary)
            if let subtitle = row.subtitle {
                Text(subtitle).font(.caption).foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private var label: some View {
        HStack {
            titles
            Spacer()
            if let value = row.value, !value.isEmpty {
                Text(value).foregroundStyle(Palette.textSecondary)
            }
            switch row.mark {
            case "included": Image(systemName: "checkmark").foregroundStyle(Palette.accent).accessibilityLabel("Selected")
            case "excluded": Image(systemName: "xmark").foregroundStyle(Palette.danger).accessibilityLabel("Excluded")
            default: EmptyView()
            }
        }
        .contentShape(Rectangle())
    }
}

/// A text row. The text goes to the source when the user presses Return or leaves the field.
private struct InputRow: View {
    let row: SourceForm.Row
    let send: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(row.title, text: $text, prompt: Text(row.title))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($focused)
            .onSubmit { commit() }
            .onChange(of: focused) { _, now in if !now { commit() } }
            .onAppear { text = row.value ?? "" }
            .onChange(of: row.value) { _, new in if !focused { text = new ?? "" } }
    }

    private func commit() {
        if text != (row.value ?? "") { send(text) }
    }
}
