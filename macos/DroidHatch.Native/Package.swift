// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DroidHatch.Native",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DroidHatchFrameTransport", targets: ["DroidHatchFrameTransport"]),
        .library(name: "DroidHatchViewer", targets: ["DroidHatchViewer"]),
        .executable(name: "droidhatch-native", targets: ["DroidHatchNative"]),
        .executable(name: "droidhatch-frame-probe", targets: ["DroidHatchFrameProbe"]),
        .executable(name: "droidhatch-gui", targets: ["DroidHatchGUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "DroidHatchFrameTransport",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics")
            ]),
        .executableTarget(name: "DroidHatchNative"),
        .executableTarget(
            name: "DroidHatchFrameProbe",
            dependencies: ["DroidHatchFrameTransport"]),
        .target(
            name: "DroidHatchViewer",
            dependencies: ["DroidHatchFrameTransport"],
            path: "Sources/DroidHatchFrameViewer",
            resources: [.copy("Resources/Shaders")]),
        .testTarget(
            name: "DroidHatchViewerTests",
            dependencies: ["DroidHatchViewer"]),
        .executableTarget(
            name: "DroidHatchGUI",
            dependencies: ["DroidHatchViewer"],
            linkerSettings: [.linkedLibrary("sqlite3")])
    ]
)
