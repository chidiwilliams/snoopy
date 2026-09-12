// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NotificationClaude",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotificationClaude", targets: ["NotificationClaude"])
    ],
    targets: [
        .executableTarget(
            name: "NotificationClaude",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
