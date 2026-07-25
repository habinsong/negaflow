// swift-tools-version: 5.9
import PackageDescription

// negaflow — macOS-native film developing app (image import + optional scanner plugins)
//   ScannerKit  : scanner abstraction + external-process plugin host (Mock 내장, SANE는 외부 플러그인)
//   Chromabase  : color developing engine (negative inversion + looks)
//   negaflow    : CLI (engine self-test on a synthetic negative)
//   negaflowApp : SwiftUI app (Import / Scan / Develop / Export)
//
// 스캐너(SANE)는 GPL 라이센스라 negaflow(Apache-2.0)에서 분리되어 외부 프로세스 플러그인으로
// 제공된다(별도 저장소: https://github.com/habinsong/negaflow-scanner-sane.git).
//
// GUI 앱(negaflowApp)은 SPM CLI 링커가 Xcode 26 SDK의 비공개 SwiftUICore를
// 링크하지 못해 swift run/swift build로 직접 실행할 수 없다. 대신 Xcode 빌드
// 시스템(xcodebuild)으로 빌드해야 한다. scripts/run-app.sh 가 이를 수행한다.
let package = Package(
    name: "negaflow",
    defaultLocalization: "en",
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
            // 네 장의 번들 TIFF 샘플은 송하빈(Song Habin, habin song)이 직접 촬영·준비했다.
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("ImageCaptureCore")]
        ),
        .target(
            name: "Chromabase",
            path: "Sources/Chromabase",
            resources: [
                .copy("ProductVersion.txt"),
                .copy("ProductBuild.txt"),
                .copy("Presets"),
                // 번들 scanner-profile JSON은 송하빈(Song Habin, habin song)이 직접 촬영한
                // 샘플 이미지와 자체 Python 처리 파이프라인으로 생성했다.
                .copy("ScannerProfiles")
            ],
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
            exclude: ["Resources/Localizable.xcstrings"],
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ImageCaptureCore"),
                .linkedLibrary("sqlite3"),
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
        .testTarget(
            name: "negaflowAppTests",
            dependencies: ["negaflowApp"],
            path: "Tests/negaflowAppTests",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "negaflowCLITests",
            dependencies: ["negaflowCLI"],
            path: "Tests/negaflowCLITests"
        ),
    ]
)
