// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Rune",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Rune",
            path: "Sources/Rune",
            linkerSettings: [
                // FoundationModels only exists on macOS 26+, and Rune still
                // deploys to 14. Weak-link it so an older Mac can load the app
                // at all and simply reports no on-device model, instead of
                // failing at launch on a missing framework.
                .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"])
            ]
        )
    ]
)
