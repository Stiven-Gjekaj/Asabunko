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

    /// "en" from "en-US" or "en_GB".
    private static func code(of language: String) -> String {
        String(language.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "")
    }
}
