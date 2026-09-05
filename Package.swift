// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VoiceFlow",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VoiceFlow",
            path: "Sources/VoiceFlow",
            exclude: ["Info.plist", "Resources"]
        )
    ]
)
