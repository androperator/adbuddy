// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ADBuddy",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "ADBuddy",
            targets: ["ADBuddy"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "ADBuddy",
            path: "Sources/ADBuddy"
        ),
    ]
)
