// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "cd2here",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "Cd2HereCore", targets: ["Cd2HereCore"])
    ],
    targets: [
        .target(
            name: "Cd2HereCore",
            path: "Shared"
        ),
        .testTarget(
            name: "Cd2HereCoreTests",
            dependencies: ["Cd2HereCore"],
            path: "Tests/Cd2HereCoreTests"
        )
    ]
)
