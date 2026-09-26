// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MeetAI",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.4", traits: []),
    ],
    targets: [
        .executableTarget(
            name: "MeetAI",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/MeetAI",
            exclude: ["Resources/Info.plist"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
            ]
        ),
    ]
)
