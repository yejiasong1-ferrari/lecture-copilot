// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LectureCopilot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LectureCopilot", targets: ["LectureCopilot"])
    ],
    targets: [
        .executableTarget(
            name: "LectureCopilot",
            path: "Sources/LectureCopilot",
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        )
    ]
)
