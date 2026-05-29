// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingGenie",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "NotchCore", targets: ["NotchCore"]),
        .executable(name: "notch", targets: ["notch"]),
        .executable(name: "selfcheck", targets: ["selfcheck"]),
    ],
    targets: [
        .target(
            name: "NotchCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "notch",
            dependencies: ["NotchCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "selfcheck",
            dependencies: ["NotchCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "NotchCoreTests",
            dependencies: ["NotchCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
