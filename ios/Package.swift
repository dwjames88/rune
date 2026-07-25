// swift-tools-version: 6.0
import PackageDescription

// Rune for iOS lives in its own package so the root stays a pure macOS
// build — `swift build` at the repo root never has to know UIKit exists.
// scripts/ios-run.sh builds this against the iphonesimulator SDK and wraps
// the binary into an .app the simulator can install; no Xcode project.
let package = Package(
    name: "RuneMobile",
    platforms: [.iOS(.v17)],
    targets: [
        .executableTarget(name: "RuneMobile", path: "Sources/RuneMobile")
    ]
)
