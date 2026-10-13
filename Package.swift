// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Toothpeek",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Toothpeek")
    ]
)
