// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FreeFlow",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FreeFlowCore", targets: ["FreeFlowCore"]),
        .executable(name: "freeflow", targets: ["FreeFlowCLI"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FreeFlowCore",
            path: "FreeFlow/Sources/Core",
            resources: [
                .copy("Lexical/profiles"),
            ]
        ),
        .executableTarget(
            name: "FreeFlowCLI",
            dependencies: ["FreeFlowCore"],
            path: "FreeFlow/Sources/CLI"
        ),
        .testTarget(
            name: "FreeFlowTests",
            dependencies: ["FreeFlowCore"],
            path: "FreeFlow/Tests"
        ),
    ]
)
