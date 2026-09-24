// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Tokarium",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Tokarium",
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
