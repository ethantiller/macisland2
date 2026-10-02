// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacIsland",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "MacIsland",
            path: "Sources/MacIsland",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MacIslandTests",
            dependencies: ["MacIsland"],
            path: "Tests/MacIslandTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
