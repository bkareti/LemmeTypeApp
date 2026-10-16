// swift-tools-version: 6.2

import PackageDescription

// Module boundaries are documented in the macos-coding-standards skill and
// docs/decisions/0002-project-structure.md. Do not add dependency edges
// without updating both.

let strictSettings: [SwiftSetting] = [
    .treatAllWarnings(as: .error)
]

let package = Package(
    name: "LemmeTypeKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Support", targets: ["Support"]),
        .library(name: "Audio", targets: ["Audio"]),
        .library(name: "Permissions", targets: ["Permissions"]),
        .library(name: "Shortcuts", targets: ["Shortcuts"]),
        .library(name: "Lifecycle", targets: ["Lifecycle"]),
        .library(name: "Recognition", targets: ["Recognition"]),
        .library(name: "ModelAssets", targets: ["ModelAssets"]),
        .library(name: "UI", targets: ["UI"]),
        .library(name: "TestSupport", targets: ["TestSupport"]),
    ],
    targets: [
        .target(name: "Domain", swiftSettings: strictSettings),
        .target(name: "Support", dependencies: ["Domain"], swiftSettings: strictSettings),
        .target(name: "Audio", dependencies: ["Domain", "Support"], swiftSettings: strictSettings),
        .target(name: "Permissions", dependencies: ["Domain", "Support"], swiftSettings: strictSettings),
        .target(name: "Shortcuts", dependencies: ["Domain", "Support"], swiftSettings: strictSettings),
        .target(name: "Lifecycle", dependencies: ["Domain", "Support"], swiftSettings: strictSettings),
        .target(name: "Recognition", dependencies: ["Domain", "Support"], swiftSettings: strictSettings),
        .target(name: "ModelAssets", dependencies: ["Domain", "Support"], swiftSettings: strictSettings),
        .target(
            name: "UI",
            dependencies: ["Domain", "Support"],
            resources: [.process("Resources")],
            swiftSettings: strictSettings
        ),
        .target(name: "TestSupport", dependencies: ["Domain"], swiftSettings: strictSettings),

        .testTarget(name: "DomainTests", dependencies: ["Domain", "TestSupport"]),
        .testTarget(name: "SupportTests", dependencies: ["Support", "Domain"]),
        .testTarget(name: "AudioTests", dependencies: ["Audio", "Domain", "TestSupport"]),
        .testTarget(name: "PermissionsTests", dependencies: ["Permissions", "Domain"]),
        .testTarget(name: "LifecycleTests", dependencies: ["Lifecycle", "Domain"]),
        .testTarget(name: "RecognitionTests", dependencies: ["Recognition", "Domain", "TestSupport"]),
        .testTarget(name: "ModelAssetsTests", dependencies: ["ModelAssets", "Domain"]),
        .testTarget(name: "ShortcutsTests", dependencies: ["Shortcuts", "Domain", "TestSupport"]),
        .testTarget(
            name: "UIModuleTests", dependencies: ["UI", "Domain", "Support", "TestSupport", "Audio", "Shortcuts"]),
    ],
    swiftLanguageModes: [.v6]
)
