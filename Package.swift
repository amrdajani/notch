// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Notch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Notch",
            path: "Sources/Notch",
            linkerSettings: [
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("EventKit")
            ]
        )
    ]
)
