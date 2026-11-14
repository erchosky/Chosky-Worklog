// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChoskyWorklog",
    defaultLocalization: "es",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ChoskyWorklog", targets: ["ChoskyWorklog"]),
        .executable(name: "ChoskyProcessGuard", targets: ["ChoskyProcessGuard"])
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .executableTarget(
            name: "ChoskyWorklog",
            dependencies: ["CSQLite"],
            path: "Sources/ChoskyWorklog",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .executableTarget(
            name: "ChoskyProcessGuard",
            path: "Sources/ChoskyProcessGuard"
        )
    ]
)
