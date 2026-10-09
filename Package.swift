// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Aura",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Aura", targets: ["AuraApp"]),
        .executable(name: "aura-cli", targets: ["aura-cli"]),
        .library(name: "AuraCore", targets: ["AuraCore"]),
        .library(name: "AuraDevices", targets: ["AuraDevices"]),
    ],
    targets: [
        // Thin C bridge over IOUSBLib control transfers (COM-style plug-in interfaces are awkward from Swift).
        .target(
            name: "AuraUSB",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        // Device-agnostic lighting engine: colors, palettes, effects, compositor, render loop.
        .target(name: "AuraCore"),
        // Hardware back-ends (device providers). Razer is the first one.
        .target(
            name: "AuraDevices",
            dependencies: ["AuraCore", "AuraUSB"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "AuraApp",
            dependencies: ["AuraCore", "AuraDevices"]
        ),
        .executableTarget(
            name: "aura-cli",
            dependencies: ["AuraCore", "AuraDevices"]
        ),
        .testTarget(name: "AuraCoreTests", dependencies: ["AuraCore"]),
        .testTarget(name: "AuraDevicesTests", dependencies: ["AuraDevices", "AuraCore"]),
    ]
)
