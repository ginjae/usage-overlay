// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UsageOverlay",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "UsageOverlay",
            path: "Sources/UsageOverlay",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
