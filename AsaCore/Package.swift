// swift-tools-version: 6.0
import PackageDescription

// The parts of the app that do not need a screen. They build and test on a Mac
// with `swift test`, so a test does not need a simulator.
let package = Package(
    name: "AsaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "AsaCore", targets: ["AsaCore"])],
    targets: [
        // libarchive is in the SDK of iOS and of macOS, with no headers.
        // shim.h declares the functions that the app uses.
        .systemLibrary(name: "CArchive", path: "Sources/CArchive"),
        .target(name: "AsaCore", dependencies: ["CArchive"], resources: [.copy("Resources/libraries.js"), .copy("Resources/host.js"), .copy("Resources/lnreader.js")]),
        .testTarget(name: "AsaCoreTests", dependencies: ["AsaCore", "CArchive"]),
    ]
)
