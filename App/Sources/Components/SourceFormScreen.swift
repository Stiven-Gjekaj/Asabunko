import AsaCore
import AuthenticationServices
import SwiftUI

/// A settings form of a source. With no `id`, the screen opens the root form of the source.
/// The source gives the form again after each action, so the rows can change.
struct SourceFormScreen: View {
    let source: OnlineSource
    let title: String
    var id: String?
    /// Runs after each change, so that the screen of the source can load its list again.
    var onChange: () -> Void = {}
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
                            FormRow(source: source, row: row, onChange: onChange) { input in act(row, input) }
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
                onChange()
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
                onChange()
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
    let onChange: () -> Void
    let act: (FormInput) -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.webAuthenticationSession) private var webAuthentication
    @State private var asking = false
    @State private var signingIn = false
    @State private var webPage: URL?
    @State private var username = ""
    @State private var password = ""

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
            Button(row.title, role: row.destructive == true ? .destructive : nil) {
                if row.confirm == nil { act(.tap) } else { asking = true }
            }
            .confirmationDialog(row.confirm ?? row.title, isPresented: $asking, titleVisibility: .visible) {
                Button(row.title, role: row.destructive == true ? .destructive : nil) { act(.tap) }
            }
        case .link:
            NavigationLink { SourceFormScreen(source: source, title: row.title, id: row.form, onChange: onChange) } label: { label }
        case .stepper:
            Stepper(value: Binding(get: { row.number ?? 0 }, set: { act(.number($0)) }),
                    in: (row.minimum ?? -Double.greatestFiniteMagnitude)...(row.maximum ?? Double.greatestFiniteMagnitude),
                    step: row.step ?? 1) {
                LabeledContent(row.title, value: row.number.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } ?? "")
            }
        case .web:
            Button { if let url = row.url.flatMap(URL.init(string:)) { openURL(url) } } label: {
                HStack {
                    Text(row.title).foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right.square").foregroundStyle(Palette.textSecondary)
                }
            }
        case .login:
            signInRow
        case .unsupported:
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).foregroundStyle(Palette.textSecondary)
                Text("Asabunko cannot do this action.").font(.caption).foregroundStyle(Palette.textSecondary)
            }
        }
    }

    /// A sign-in: a user name and a password, a page in a web view, or an OAuth page. A tap on a done sign-in signs out.
    @ViewBuilder private var signInRow: some View {
        let login = row.login
        Button {
            guard let login else { return }
            if login.signedIn {
                asking = true
            } else if login.method == "basic" {
                username = login.username ?? ""
                password = ""
                signingIn = true
            } else if login.method == "web" {
                webPage = login.url.flatMap(URL.init(string:))
            } else {
                oauth(login)
            }
        } label: { label }
        .confirmationDialog(row.title, isPresented: $asking, titleVisibility: .visible) {
            Button(row.title, role: .destructive) {
                act(.logout)
                if login?.clearsCookies == true, let host = login?.url.flatMap(URL.init(string:))?.host {
                    Task { await SignInSheet.removeCookies(of: host) }
                }
            }
        }
        .alert(row.title, isPresented: $signingIn) {
            TextField(login?.useEmail == true ? "Email" : "User name", text: $username)
                .textContentType(login?.useEmail == true ? .emailAddress : .username)
                .keyboardType(login?.useEmail == true ? .emailAddress : .default)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password).textContentType(.password)
            Button("Cancel", role: .cancel) {}
            Button("Sign in") { act(.login(username: username, password: password)) }
        }
        .sheet(item: $webPage) { url in
            SignInSheet(url: url, storageKeys: login?.storageKeys ?? []) { result in
                webPage = nil
                if let result { act(.web(cookies: result.cookies, storage: result.storage)) }
            }
        }
    }

    private func oauth(_ login: SourceForm.Login) {
        guard let url = login.url.flatMap(URL.init(string:)) else { return }
        Task {
            if let callback = try? await webAuthentication.authenticate(using: url, callbackURLScheme: login.callbackScheme ?? "aidoku",
                                                                         preferredBrowserSession: .shared) {
                act(.callback(callback))
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
        field
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($focused)
            .onSubmit { commit() }
            .onChange(of: focused) { _, now in if !now { commit() } }
            .onAppear { text = row.value ?? "" }
            .onChange(of: row.value) { _, new in if !focused { text = new ?? "" } }
    }

    @ViewBuilder private var field: some View {
        if row.secure == true {
            SecureField(row.title, text: $text, prompt: Text(row.title))
        } else {
            TextField(row.title, text: $text, prompt: Text(row.title))
        }
    }

    private func commit() {
        guard text != (row.value ?? "") else { return }
        send(text)
        // A field with no value adds an entry to a list, so it is empty again for the next entry.
        if row.value == nil { text = "" }
    }
}
