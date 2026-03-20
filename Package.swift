// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FreeFlow",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FreeFlowCore", targets: ["FreeFlowCore"]),
        .executable(name: "freeflow", targets: ["FreeFlowCLI"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FreeFlowCore",
            path: "FreeFlow/Sources/Core"
        ),
        .executableTarget(
            name: "FreeFlowCLI",
            dependencies: ["FreeFlowCore"],
            path: "FreeFlow/Sources/App"
        ),
        .testTarget(
            name: "FreeFlowTests",
            dependencies: ["FreeFlowCore"],
            path: "FreeFlow/Tests"
        ),
    ]
)
