// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Rune",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Rune",
            path: "Sources/Rune"
        )
    ]
)
