// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MeetBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MeetBarCore", targets: ["MeetBarCore"]),
        .executable(name: "MeetBar", targets: ["MeetBar"])
    ],
    targets: [
        .target(name: "MeetBarCore"),
        .executableTarget(
            name: "MeetBar",
            dependencies: ["MeetBarCore"]
        ),
        .executableTarget(
            name: "MeetBarSmokeTests",
            dependencies: ["MeetBarCore"]
        ),
        .testTarget(
            name: "MeetBarCoreTests",
            dependencies: ["MeetBarCore"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
