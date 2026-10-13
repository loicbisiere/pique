// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Pique",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Pique")
    ]
)
