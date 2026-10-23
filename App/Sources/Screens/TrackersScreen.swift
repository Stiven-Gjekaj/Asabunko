import AsaCore
import AuthenticationServices
import SwiftUI

/// The sign-in to AniList and MyAnimeList. The app has no client of its own on these sites,
/// so the user registers a client and gives its ID here.
struct TrackersScreen: View {
    var body: some View {
        Form {
            ForEach(TrackerKind.allCases) { kind in TrackerSection(kind: kind) }
        }
        .asaForm()
        .asaScreen()
        .navigationTitle("Trackers")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TrackerSection: View {
    let kind: TrackerKind
    @Environment(AppModel.self) private var app
    @Environment(\.webAuthenticationSession) private var webAuthentication
    @AppStorage private var clientID: String
    @State private var signedIn: Bool
    @State private var working = false

    init(kind: TrackerKind) {
        self.kind = kind
        _clientID = AppStorage(wrappedValue: "", TrackerAccounts.clientKey(kind))
        _signedIn = State(initialValue: TrackerAccounts.token(kind) != nil)
    }

    var body: some View {
        Section {
            TextField("Client ID", text: $clientID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("\(kind.name) client ID")
            if signedIn {
                LabeledContent(kind.name, value: "Signed in")
                Button("Sign out of \(kind.name)", role: .destructive) {
                    TrackerAccounts.setToken(nil, for: kind)
                    signedIn = false
                }
            } else {
                Button {
                    Task { await signIn() }
                } label: {
                    HStack {
                        Text("Sign in to \(kind.name)")
                        if working { Spacer(); ProgressView() }
                    }
                }
                .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty || working)
            }
        } header: {
            Text(kind.name)
        } footer: {
            Text("Register a client on \(kind.name) with the redirect URI \(kind.redirect), and paste its ID here. Then hold a book in the Library and choose Track.")
        }
    }

    private func signIn() async {
        working = true
        defer { working = false }
        let tracker = TrackerAccounts.tracker(kind)
        let verifier = Self.verifier()
        let state = UUID().uuidString
        do {
            let callback = try await webAuthentication.authenticate(
                using: tracker.signInURL(verifier: verifier, state: state), callbackURLScheme: "asabunko", preferredBrowserSession: .shared)
            let token = try await tracker.token(from: callback, verifier: verifier)
            TrackerAccounts.setToken(token, for: kind)
            signedIn = true
        } catch ASWebAuthenticationSessionError.canceledLogin {
        } catch {
            app.fault = "The sign-in to \(kind.name) did not work: \(error.localizedDescription)"
        }
    }

    /// A code verifier of PKCE: 64 characters of the unreserved set.
    private static func verifier() -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<64).map { _ in characters.randomElement()! })
    }
}

/// Links a book to an entry of a tracker: a search with the title of the book, then a tap on the entry.
struct TrackSheet: View {
    let bookID: Book.ID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var kind = TrackerKind.allCases.first { TrackerAccounts.token($0) != nil } ?? .anilist
    @State private var query = ""
    @State private var hits: [TrackerHit] = []
    @State private var searching = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tracker", selection: $kind) {
                        ForEach(TrackerKind.allCases) { Text($0.name).tag($0) }
                    }
                    if let link = app.book(bookID)?.tracking.first(where: { $0.kind == kind }) {
                        LabeledContent("Linked to", value: link.title)
                        Button("Stop tracking", role: .destructive) { app.untrack(bookID, from: kind) }
                    }
                }
                if TrackerAccounts.token(kind) == nil {
                    Section { Text("Sign in to \(kind.name) in Settings, Trackers.").foregroundStyle(Palette.textSecondary) }
                } else {
                    Section {
                        HStack {
                            TextField("Title", text: $query).onSubmit { Task { await search() } }
                            Button("Search") { Task { await search() } }.disabled(query.isEmpty || searching)
                        }
                        if searching { ProgressView() }
                        if let failure { Text(failure).foregroundStyle(Palette.danger) }
                        ForEach(hits) { hit in
                            Button {
                                app.track(bookID, with: hit, on: kind)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.title).foregroundStyle(Palette.textPrimary)
                                    if let chapters = hit.chapters {
                                        Text("\(chapters) chapters").font(Karla.font(13)).foregroundStyle(Palette.textSecondary)
                                    }
                                }
                            }
                        }
                    } footer: {
                        Text("The tracker gets the number of chapters that you read, each time it goes up.")
                    }
                }
            }
            .asaForm()
            .asaScreen()
            .navigationTitle("Track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: kind) {
                if query.isEmpty { query = app.book(bookID)?.title ?? "" }
                hits = []
                if TrackerAccounts.token(kind) != nil { await search() }
            }
        }
    }

    private func search() async {
        searching = true
        failure = nil
        defer { searching = false }
        do {
            hits = try await TrackerAccounts.tracker(kind).search(query)
            if hits.isEmpty { failure = "\(kind.name) has no title with these words." }
        } catch {
            failure = error.localizedDescription
        }
    }
}
