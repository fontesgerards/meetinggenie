// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingGenie",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "NotchCore", targets: ["NotchCore"]),
        .executable(name: "notch", targets: ["notch"]),
        .executable(name: "MeetingGenie", targets: ["MeetingGenieApp"]),
        .executable(name: "overlay-spike", targets: ["OverlaySpike"]),
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
            name: "MeetingGenieApp",
            dependencies: ["NotchCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            // When bundled, the app loads Sparkle.framework from
            // Contents/Frameworks; a SwiftPM executable needs this rpath
            // injected or it crashes at launch once bundled (it resolves via
            // DYLD under `swift run`, masking the problem). Plan U1/U2.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks"])]
        ),
        .executableTarget(
            name: "OverlaySpike",
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
