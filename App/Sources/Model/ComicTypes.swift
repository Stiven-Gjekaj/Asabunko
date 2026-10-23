import UniformTypeIdentifiers

/// The kinds of file that the importer offers. Info.plist declares the comic archives, FB2, MOBI, and AZW3.
enum ComicTypes {
    static let all: [UTType] = {
        let declared = ["cbz", "cbr", "cb7", "cbt", "rar", "7z", "fb2", "mobi", "azw3"].map {
            UTType(importedAs: "io.github.stivengjekaj.asabunko.\($0)")
        }
        return declared + [.zip, UTType("public.tar-archive"), .epub, .pdf, .plainText, .html, .folder].compactMap { $0 }
    }()
}
