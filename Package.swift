// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacStats",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacStats", targets: ["MacStats"])
    ],
    targets: [
        .executableTarget(
            name: "MacStats",
            dependencies: ["SensorBridge"],
            path: "Sources/MacStats",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .target(
            name: "SensorBridge",
            path: "Sources/SensorBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "MacStatsTests",
            dependencies: ["MacStats"],
            path: "Tests/MacStatsTests"
        )
    ]
)
