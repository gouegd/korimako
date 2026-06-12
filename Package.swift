// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "sound-keko",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "sound-keko",
            path: "Sources/sound-keko",
            // AppKit + manual threading; Swift 5 mode keeps strict-concurrency
            // checks from fighting the POSIX socket / callback design.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
