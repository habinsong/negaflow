// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ICADetect",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ICADetect",
            path: ".",
            exclude: ["Package.swift"],
            linkerSettings: [
                .linkedFramework("ImageCaptureCore"),
                .linkedFramework("Cocoa"),
            ]
        ),
    ]
)
