// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "korimako",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "korimako",
            path: "Sources/korimako",
            // AppKit + manual threading; Swift 5 mode keeps strict-concurrency
            // checks from fighting the POSIX socket / callback design.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
