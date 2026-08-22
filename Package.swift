// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ADBuddy",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ADBuddyCore",
            targets: ["ADBuddyCore"]
        ),
        .executable(
            name: "ADBuddy",
            targets: ["ADBuddy"]
        ),
        .executable(
            name: "adbuddy-mcp",
            targets: ["ADBuddyMCP"]
        ),
    ],
    targets: [
        .target(
            name: "ADBuddyCore",
            path: "Sources/ADBuddyCore"
        ),
        .executableTarget(
            name: "ADBuddy",
            dependencies: ["ADBuddyCore"],
            path: "Sources/ADBuddy"
        ),
        .executableTarget(
            name: "ADBuddyMCP",
            dependencies: ["ADBuddyCore"],
            path: "Sources/ADBuddyMCP"
        ),
        .testTarget(
            name: "ADBuddyTests",
            dependencies: ["ADBuddy", "ADBuddyCore", "ADBuddyMCP"],
            path: "Tests/ADBuddyTests"
        ),
    ]
)
