// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "jietu",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "jietu",
            targets: ["jietu"]
        )
    ],
    targets: [
        .executableTarget(
            name: "jietu",
            resources: [
                .process("Assets.xcassets")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Translation"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("Vision")
            ]
        )
    ]
)
