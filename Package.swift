// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Prism",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Prism",
            path: "Sources/Prism"
        )
    ]
)
