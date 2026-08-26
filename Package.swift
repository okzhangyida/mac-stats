// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacStats",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacStats", targets: ["MacStats"])
    ],
    targets: [
        .executableTarget(
            name: "MacStats",
            dependencies: ["SensorBridge"],
            path: "Sources/MacStats",
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
        )
    ]
)
