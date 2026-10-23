import Foundation

/// Chooses the sources of a list that the app installs with no question.
public enum SourceLanguages {
    /// Codes of sources for all languages.
    private static let everyLanguage: Set<String> = ["", "multi", "all", "global", "international"]

    /// True when the source is in one of the languages, such as "en" or "en-US", or in all languages.
    /// A list can give a code, such as "en", or a name, such as "English".
    public static func matches(_ language: String, preferred: [String]) -> Bool {
        let value = language.trimmingCharacters(in: .whitespaces).lowercased()
        if everyLanguage.contains(value) { return true }
        let codes = Set(preferred.map { code(of: $0) })
        if codes.contains(code(of: value)) { return true }
        let english = Locale(identifier: "en")
        return codes.contains { english.localizedString(forLanguageCode: $0)?.lowercased() == value }
    }

    /// The sources to install: in the languages, and not for adults when `adult` is false.
    public static func pick(_ sources: [SourceInfo], preferred: [String], adult: Bool) -> [SourceInfo] {
        sources.filter { (adult || !$0.adult) && matches($0.language, preferred: preferred) }
    }

    /// The changes to the sources of one list after a save of the source list. The app installs the English
    /// sources that are not on the device yet, and removes the installed sources that left the list. The other
    /// installed sources stay as they are, so a save does not download them again.
    public static func sync(_ available: [SourceInfo], installed: Set<String>, adult: Bool) -> (install: [SourceInfo], remove: Set<String>) {
        let install = pick(available, preferred: ["en"], adult: adult).filter { !installed.contains($0.id) }
        let remove = installed.subtracting(available.map(\.id))
        return (install, remove)
    }

    /// "en" from "en-US" or "en_GB".
    private static func code(of language: String) -> String {
        String(language.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "")
    }
}
