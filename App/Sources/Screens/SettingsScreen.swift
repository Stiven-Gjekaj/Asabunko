import AsaCore
import SwiftUI

/// The look, the reader, and the facts about the app.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Appearance.key) private var appearance = Appearance.system
    @State private var showFontLicense = false
    @State private var newer: String?
    @AppStorage("browse.adult") private var adult = false
    @State private var exporting: BackupFile?
    @State private var restoring = false
    @State private var pending: Backup?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Look") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.name).tag($0) }
                    }
                }
                Section {
                    Picker("Reading mode", selection: Binding(get: { app.library.defaultMode }, set: { app.setDefaultMode($0) })) {
                        ForEach(ReadingMode.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                } header: {
                    Text("Reader")
                } footer: {
                    Text("A book uses this mode until you choose a mode for it in the reader. A comic with \"YesAndRightToLeft\" in its ComicInfo.xml opens from the right to the left.")
                }
                Section {
                    Button("Save a backup") {
                        do { exporting = BackupFile(data: try app.backup()) } catch { message = error.localizedDescription }
                    }
                    Button("Restore a backup") { restoring = true }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("The backup is one file with your books, your places, your sources, and the chapters of your online books. It does not hold the files of your books or the passwords of your sources. Keep it in Files or in iCloud Drive.")
                }
                Section {
                    Toggle("Show sources for adults", isOn: $adult)
                } header: {
                    Text("Sources")
                } footer: {
                    Text("A list marks some sources for adults. Asabunko hides them until you turn this on.")
                }
                Section {
                    if let newer {
                        Link(destination: URL(string: AppInfo.repository + "/releases/latest")!) {
                            Label("Version \(newer) is available", systemImage: "arrow.down.circle")
                        }
                        .font(Karla.font(16, .bold))
                    }
                    Link(destination: URL(string: AppInfo.kofi)!) {
                        Label("Support the project on Ko-fi", systemImage: "cup.and.saucer")
                    }
                    Link(destination: URL(string: AppInfo.repository)!) {
                        Label("Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    LabeledContent("Version", value: AppInfo.version)
                } header: {
                    Text("About")
                } footer: {
                    Text("Asabunko keeps your books on this device. It has no account and no analytics. The app asks GitHub for the newest version.")
                }
                Section("Licenses") {
                    Text("The code is under the MIT License. Karla, the font of the app, is under the SIL Open Font License, Version 1.1. The archives open with libarchive, under the BSD License.")
                        .foregroundStyle(Palette.textSecondary)
                    Button(showFontLicense ? "Hide the font license" : "Show the font license") {
                        showFontLicense.toggle()
                    }
                    if showFontLicense {
                        Text(Self.fontLicense)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Palette.textSecondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .asaForm()
            .asaScreen()
            .navigationTitle("Settings")
                        .task { newer = await UpdateCheck.newerVersion() }
            .fileExporter(
                isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
                document: exporting, contentType: .json,
                defaultFilename: "Asabunko " + Date.now.formatted(.iso8601.year().month().day())
            ) { _ in exporting = nil }
            .fileImporter(isPresented: $restoring, allowedContentTypes: [.json]) { result in
                guard case let .success(url) = result else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    pending = try Backup.decode(Data(contentsOf: url))
                } catch Backup.Failure.newer {
                    message = "A newer version of Asabunko made this backup. Update the app first."
                } catch {
                    message = "This file is not a backup of Asabunko."
                }
            }
            .confirmationDialog(
                "Restore the backup?",
                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                titleVisibility: .visible
            ) {
                Button("Restore", role: .destructive) {
                    guard let backup = pending else { return }
                    pending = nil
                    Task {
                        let skipped = await app.restore(backup)
                        message = skipped.isEmpty ? "The backup is restored."
                            : "The backup is restored. Import these books again, because their files are not on this device:\n\n" + skipped.joined(separator: "\n")
                    }
                }
            } message: {
                Text("The backup takes the place of your library and your sources. Your online books come back, and their chapters download again.")
            }
            .alert("Backup", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    /// The text of the SIL Open Font License, from the file next to the font.
    static var fontLicense: String {
        guard let url = Bundle.main.url(forResource: "Karla-OFL", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "SIL Open Font License, Version 1.1: https://openfontlicense.org" }
        return text
    }
}
