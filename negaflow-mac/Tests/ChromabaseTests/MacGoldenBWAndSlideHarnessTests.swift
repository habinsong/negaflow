import CoreImage
import Foundation
import XCTest
@testable import Chromabase

/// REQUEST-5 요청 E의 실입력 흑백 네거티브·컬러 포지티브 골든을 방출한다.
///
/// ```
/// NEGAFLOW_BW_GOLDEN_INPUT=/path/to/bw.tiff \
/// NEGAFLOW_SLIDE_GOLDEN_INPUT=/path/to/slide.tiff \
/// NEGAFLOW_BW_SLIDE_GOLDEN_DIR=/path/to/docs/verification/macos-golden/task9-bw-slide \
/// swift test --filter MacGoldenBWAndSlideHarnessTests
/// ```
///
/// 하네스는 사용한 원본을 각 디렉터리의 `source.tiff`로 복제한다. 이미 같은 SHA-256의
/// 원본이 있으면 그대로 재사용하고, 다른 파일이면 덮어쓰지 않고 실패한다.
final class MacGoldenBWAndSlideHarnessTests: XCTestCase {
    private struct Fixture {
        let name: String
        let filmType: FilmType
        let inputKey: String
        let scannerProfileID: String?
        let chemistryProvenance: String
    }

    private struct Case {
        let name: String
        let target: DevelopTarget
        let scannerProfileID: String?
        let colorSpace: ExportColorSpace
    }

    func testEmitsBWAndSlideGolden() throws {
        guard let root = MacGoldenHarness.outputDirectory("NEGAFLOW_BW_SLIDE_GOLDEN_DIR") else {
            throw XCTSkip("NEGAFLOW_BW_SLIDE_GOLDEN_DIR 를 지정하면 흑백·슬라이드 골든을 생성합니다.")
        }
        for fixture in Self.fixtures {
            let input = try XCTUnwrap(
                MacGoldenHarness.inputURL(fixture.inputKey),
                "\(fixture.inputKey) 이 지정되지 않았습니다."
            )
            try emit(fixture: fixture, input: input, directory: root.appendingPathComponent(fixture.name))
        }
    }

    private func emit(fixture: Fixture, input: URL, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let copiedSource = directory.appendingPathComponent("source.tiff")
        try copyInputIfNeeded(input, to: copiedSource)

        let engine = ChromabaseEngine()
        let raw = try XCTUnwrap(engine.loadScannerImage(input), "스캔 TIFF 로드 실패: \(input.path)")
        let base = fixture.filmType == .bwNegative
            ? try XCTUnwrap(
                engine.estimateFilmBase(in: raw, mode: .auto, filmType: fixture.filmType),
                "흑백 auto base 추정 실패"
            )
            : nil

        var records: [[String: Any]] = []
        for testCase in Self.cases(for: fixture) {
            var params = DevelopParameters()
            params.filmType = fixture.filmType
            params.developTarget = testCase.target
            params.scannerProfileID = testCase.scannerProfileID
            if let profileID = testCase.scannerProfileID {
                XCTAssertNotNil(ScannerProfileRegistry.load(named: profileID), "스캐너 프로파일 없음: \(profileID)")
            }

            let options = ExportOptions(
                colorSpace: testCase.colorSpace,
                tiffCompression: .none,
                tiffBitDepth: .sixteen,
                metadataPolicy: .minimal
            )
            let output = directory.appendingPathComponent("\(testCase.name).tif")
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
                "scannerProfile": testCase.scannerProfileID ?? "none",
                "exportColorSpace": testCase.colorSpace.rawValue,
                "file": output.lastPathComponent,
                "sha256": try MacGoldenHarness.sha256(of: output),
                "bytes": try MacGoldenHarness.byteCount(of: output),
            ])
        }

        var manifest: [String: Any] = [
            "schemaVersion": 1,
            "task": "REQUEST-5 E · real-input \(fixture.name) pixel golden",
            "input": [
                "file": copiedSource.lastPathComponent,
                "sha256": try MacGoldenHarness.sha256(of: copiedSource),
                "bytes": try MacGoldenHarness.byteCount(of: copiedSource),
                "pixelWidth": Int(raw.extent.width),
                "pixelHeight": Int(raw.extent.height),
                "originalPathAtCapture": input.path,
            ],
            "fixedSettings": [
                "loadPath": "ImageLoader.loadScannerTIFF",
                "developPath": "ChromabaseEngine.developScanner",
                "filmType": fixture.filmType.rawValue,
                "look": "none (plain DevelopParameters())",
                "toneOverrides": "none",
                "defectRemoval": 0,
                "exportFormat": "tiff16",
                "tiffBitDepth": 16,
                "tiffCompression": "none",
                "metadataPolicy": "minimal",
                "exportMeta": "nil",
                "chemistryProvenance": fixture.chemistryProvenance,
            ],
            "cases": records,
        ]
        if let base {
            manifest["measuredBase"] = [
                "r": base.rgb.x, "g": base.rgb.y, "b": base.rgb.z, "source": base.source.rawValue,
            ]
        }
        if fixture.scannerProfileID == nil {
            manifest["notApplicableCases"] = [
                "b-main-scannerprofile: no compatible B&W scanner profile is bundled; no color-negative profile was substituted",
            ]
        }
        try MacGoldenHarness.writeJSON(manifest, to: directory.appendingPathComponent("manifest.json"))
    }

    private func copyInputIfNeeded(_ input: URL, to destination: URL) throws {
        let sourceHash = try MacGoldenHarness.sha256(of: input)
        if FileManager.default.fileExists(atPath: destination.path) {
            XCTAssertEqual(
                try MacGoldenHarness.sha256(of: destination), sourceHash,
                "기존 source.tiff가 현재 지정한 입력과 달라 덮어쓰지 않습니다."
            )
            return
        }
        try FileManager.default.copyItem(at: input, to: destination)
        XCTAssertEqual(try MacGoldenHarness.sha256(of: destination), sourceHash)
    }

    private static func cases(for fixture: Fixture) -> [Case] {
        var cases = [
            Case(name: "a-default-main-srgb", target: .main, scannerProfileID: nil, colorSpace: .sRGB),
        ]
        if let profileID = fixture.scannerProfileID {
            cases.append(Case(
                name: "b-main-scannerprofile-srgb",
                target: .main,
                scannerProfileID: profileID,
                colorSpace: .sRGB
            ))
        }
        cases += [
            Case(name: "c-target-hs-srgb", target: .noritsu, scannerProfileID: nil, colorSpace: .sRGB),
            Case(name: "c-target-sp-srgb", target: .sp3000, scannerProfileID: nil, colorSpace: .sRGB),
            Case(name: "c-target-f135-srgb", target: .f135, scannerProfileID: nil, colorSpace: .sRGB),
            Case(name: "c-target-hr-srgb", target: .hr, scannerProfileID: nil, colorSpace: .sRGB),
            Case(name: "d-main-displayp3", target: .main, scannerProfileID: nil, colorSpace: .displayP3),
            Case(name: "d-main-adobergb", target: .main, scannerProfileID: nil, colorSpace: .adobeRGB),
        ]
        return cases
    }

    private static let fixtures = [
        Fixture(
            name: "bw-negative",
            filmType: .bwNegative,
            inputKey: "NEGAFLOW_BW_GOLDEN_INPUT",
            scannerProfileID: nil,
            chemistryProvenance: "not recorded in the local TIFF; treated only as a B&W-negative path golden"
        ),
        Fixture(
            name: "color-positive-slide",
            filmType: .colorPositive,
            inputKey: "NEGAFLOW_SLIDE_GOLDEN_INPUT",
            scannerProfileID: "noritsu__color-slide__kodak-ektachrome-100",
            chemistryProvenance: "not recorded in the local TIFF; treated only as a color-positive slide path golden"
        ),
    ]
}
