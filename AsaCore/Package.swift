// swift-tools-version: 6.0
import PackageDescription

// The parts of the app that do not need a screen. They build and test on a Mac
// with `swift test`, so a test does not need a simulator.
let package = Package(
    name: "AsaCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "AsaCore", targets: ["AsaCore"])],
    dependencies: [
        // A WebAssembly interpreter in Swift, for the sources of Aidoku. Apache License 2.0.
        .package(url: "https://github.com/swiftwasm/WasmKit", exact: "0.4.2"),
        // An HTML parser with CSS selectors, as jsoup, for the html functions of Aidoku. MIT License.
        .package(url: "https://github.com/scinfu/SwiftSoup", exact: "2.14.3"),
    ],
    targets: [
        // libarchive is in the SDK of iOS and of macOS, with no headers.
        // shim.h declares the functions that the app uses.
        .systemLibrary(name: "CArchive", path: "Sources/CArchive"),
        .target(name: "AsaCore", dependencies: ["CArchive", .product(name: "WasmKit", package: "WasmKit"), .product(name: "SwiftSoup", package: "SwiftSoup")], resources: [.copy("Resources/libraries.js"), .copy("Resources/host.js"), .copy("Resources/lnreader.js"), .copy("Resources/paperback.js")]),
        .testTarget(name: "AsaCoreTests", dependencies: ["AsaCore", "CArchive", .product(name: "WAT", package: "WasmKit")]),
    ]
)
