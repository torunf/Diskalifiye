// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Diskalifiye",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Diskalifiye", path: "Sources/Diskalifiye")
    ]
)
