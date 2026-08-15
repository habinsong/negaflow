import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import Chromabase

/// [작업 1] 실입력 픽셀 golden — 같은 스캔 한 장을 조건별로 현상·내보내고 결과를 남긴다.
///
/// 실행 예:
/// ```
/// NEGAFLOW_GOLDEN_DIR=/path/to/docs/verification/macos-golden/task1-pixels \
/// NEGAFLOW_GOLDEN_INPUT=/path/to/GT-X900_frame_4.tiff \
/// swift test --filter MacGoldenDevelopExportHarnessTests
/// ```
///
/// 조건은 전부 "스캐너 raw 경로"(`loadScannerTIFF` + `developScanner`)를 쓴다. 대상 파일이
/// 스캐너 플러그인 산출물이고, 앱의 스캔 프레임 현상 경로와 같은 경로이기 때문이다.
/// CLI 로는 `negaflow develop <in> <out.tif> --raw --look none --film-type colorNegative`
/// 가 같은 조합이다(내보내기 기본값 = sRGB / 16bit / 무압축 / metadata minimal).
final class MacGoldenDevelopExportHarnessTests: XCTestCase {

    private struct Case {
        let name: String
        let target: DevelopTarget
        let scannerProfileID: String?
        let colorSpace: ExportColorSpace
    }

    func testEmitsDevelopExportGolden() throws {
        guard let outputDirectory = MacGoldenHarness.outputDirectory() else {
            throw XCTSkip("NEGAFLOW_GOLDEN_DIR 를 지정하면 golden 을 생성합니다.")
        }
        let input = try XCTUnwrap(
            MacGoldenHarness.inputURL("NEGAFLOW_GOLDEN_INPUT"),
            "NEGAFLOW_GOLDEN_INPUT 이 지정되지 않았습니다."
        )

        let engine = ChromabaseEngine()
        let raw = try XCTUnwrap(engine.loadScannerImage(input), "스캔 TIFF 로드 실패: \(input.path)")
        // base 는 입력이 같으면 조건과 무관하게 같다. 한 번만 재고 전 조건이 공유한다 —
        // 조건 사이의 차이가 오직 target/profile/colorSpace 에서만 오도록 고정하는 것이다.
        let base = try XCTUnwrap(
            engine.estimateFilmBase(in: raw, mode: .auto),
            "auto base 추정 실패"
        )

        var records: [[String: Any]] = []
        for testCase in Self.cases {
            var params = DevelopParameters()
            params.filmType = .colorNegative
            params.developTarget = testCase.target
            params.scannerProfileID = testCase.scannerProfileID
            if let id = testCase.scannerProfileID {
                XCTAssertNotNil(ScannerProfileRegistry.load(named: id), "스캐너 프로파일 없음: \(id)")
            }

            let options = ExportOptions(
                colorSpace: testCase.colorSpace,
                tiffCompression: .none,
                tiffBitDepth: .sixteen,
                metadataPolicy: .minimal
            )
            let output = outputDirectory.appendingPathComponent("\(testCase.name).tif")
            let developed = engine.developScanner(image: raw, base: base, params: params)
            try ExportEngine.write(
                developed,
                to: output,
                format: .tiff16,
                using: ChromabaseEngine.sharedLinearRenderContext,
                metadata: nil,
                options: options
            )

            records.append([
                "case": testCase.name,
                "developTarget": testCase.target.rawValue,
                "developTargetLabel": testCase.target.displayName,
                "scannerProfile": testCase.scannerProfileID ?? "none",
                "exportColorSpace": testCase.colorSpace.rawValue,
                "file": output.lastPathComponent,
                "sha256": try MacGoldenHarness.sha256(of: output),
                "bytes": try MacGoldenHarness.byteCount(of: output),
            ])
        }

        let manifest: [String: Any] = [
            "task": "1 · real-input pixel golden",
            "input": [
                "path": input.path,
                "sha256": try MacGoldenHarness.sha256(of: input),
                "bytes": try MacGoldenHarness.byteCount(of: input),
                "pixelWidth": Int(raw.extent.width),
                "pixelHeight": Int(raw.extent.height),
            ],
            "fixedSettings": [
                "loadPath": "ImageLoader.loadScannerTIFF (CLI: --raw)",
                "developPath": "ChromabaseEngine.developScanner",
                "filmType": FilmType.colorNegative.rawValue,
                "look": "none (no preset applied — plain DevelopParameters())",
                "baseEstimationMode": "auto",
                "toneOverrides": "none",
                "defectRemoval": 0,
                "exportFormat": "tiff16",
                "tiffBitDepth": 16,
                "tiffCompression": "none",
                "metadataPolicy": "minimal",
                "exportMeta": "nil",
            ],
            "measuredBase": [
                "r": base.rgb.x, "g": base.rgb.y, "b": base.rgb.z,
                "source": base.source.rawValue,
            ],
            "cases": records,
        ]
        try MacGoldenHarness.writeJSON(
            manifest,
            to: outputDirectory.appendingPathComponent("manifest.json")
        )
    }

    private static let cases: [Case] = [
        // a) 기본
        Case(name: "a-default-main-srgb", target: .main, scannerProfileID: nil, colorSpace: .sRGB),
        // b) + 스캐너 프로파일
        Case(
            name: "b-main-scannerprofile-portra400-srgb",
            target: .main,
            scannerProfileID: "noritsu__color-nega__kodak-portra-400",
            colorSpace: .sRGB
        ),
        // c) 현상 타깃
        Case(name: "c-target-hs-srgb", target: .noritsu, scannerProfileID: nil, colorSpace: .sRGB),
        Case(name: "c-target-sp-srgb", target: .sp3000, scannerProfileID: nil, colorSpace: .sRGB),
        Case(name: "c-target-f135-srgb", target: .f135, scannerProfileID: nil, colorSpace: .sRGB),
        Case(name: "c-target-hr-srgb", target: .hr, scannerProfileID: nil, colorSpace: .sRGB),
        // d) 출력 색공간 (sRGB 는 a) 와 동일 조건이라 재사용한다)
        Case(name: "d-main-displayp3", target: .main, scannerProfileID: nil, colorSpace: .displayP3),
        Case(name: "d-main-adobergb", target: .main, scannerProfileID: nil, colorSpace: .adobeRGB),
    ]
}
