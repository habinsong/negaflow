// swift-tools-version: 5.9
import PackageDescription

// negaflow — macOS-native film scanning & developing app
//   ScannerKit  : scanner-control abstraction (ICA / SANE / Mock)
//   Chromabase  : color developing engine (negative inversion + looks)
//   negaflow    : CLI (engine self-test on a synthetic negative)
//   negaflowApp : SwiftUI app (Scan / Develop / Export)
//
// GUI 앱(negaflowApp)은 SPM CLI 링커가 Xcode 26 SDK의 비공개 SwiftUICore를
// 링크하지 못해 swift run/swift build로 직접 실행할 수 없다. 대신 Xcode 빌드
// 시스템(xcodebuild)으로 빌드해야 한다. scripts/run-app.sh 가 이를 수행한다.
// swift test는 어떤 테스트 타겟도 negaflowApp에 의존하지 않으므로 영향이 없다.
let package = Package(
    name: "negaflow",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ScannerKit", targets: ["ScannerKit"]),
        .library(name: "Chromabase", targets: ["Chromabase"]),
        .executable(name: "negaflow", targets: ["negaflowCLI"]),
        .executable(name: "negaflowApp", targets: ["negaflowApp"]),
    ],
    targets: [
        .target(
            name: "ScannerKit",
            dependencies: ["Chromabase"],
            path: "Sources/ScannerKit",
            linkerSettings: [.linkedFramework("ImageCaptureCore")]
        ),
        .target(
            name: "Chromabase",
            path: "Sources/Chromabase",
            resources: [.copy("Presets")],
            linkerSettings: [
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
                .linkedFramework("Foundation"),
            ]
        ),
        .executableTarget(
            name: "negaflowCLI",
            dependencies: ["ScannerKit", "Chromabase"],
            path: "Sources/negaflowCLI"
        ),
        .executableTarget(
            name: "negaflowApp",
            dependencies: ["ScannerKit", "Chromabase"],
            path: "Sources/negaflowApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ImageCaptureCore"),
            ]
        ),
        .testTarget(
            name: "ScannerKitTests",
            dependencies: ["ScannerKit"],
            path: "Tests/ScannerKitTests"
        ),
        .testTarget(
            name: "ChromabaseTests",
            dependencies: ["Chromabase"],
            path: "Tests/ChromabaseTests"
        ),
    ]
)
