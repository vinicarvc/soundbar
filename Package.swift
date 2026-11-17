// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SoundBar",
    platforms: [.macOS("14.2")],
    targets: [
        .executableTarget(name: "SoundBar", path: "Sources/SoundBar")
    ]
)
