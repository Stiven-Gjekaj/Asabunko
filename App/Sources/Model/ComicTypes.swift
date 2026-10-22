import UniformTypeIdentifiers

/// The kinds of file that the importer offers. Info.plist declares the comic archives.
enum ComicTypes {
    static let all: [UTType] = {
        let declared = ["cbz", "cbr", "cb7", "cbt", "rar", "7z"].map {
            UTType(importedAs: "io.github.stivengjekaj.asabunko.\($0)")
        }
        return declared + [.zip, UTType("public.tar-archive"), .folder].compactMap { $0 }
    }()
}
