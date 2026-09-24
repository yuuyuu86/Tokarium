// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Tokarium",
    platforms: [.macOS(.v14)],
    dependencies: [
        // 直接配布版の自動アップデート
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Tokarium",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Tokarium",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "TokariumTests",
            dependencies: ["Tokarium"],
            path: "Tests/TokariumTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
