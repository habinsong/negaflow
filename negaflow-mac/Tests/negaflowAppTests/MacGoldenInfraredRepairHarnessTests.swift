import Chromabase
import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import negaflowApp

/// [작업 3] GrainMend 복원 크기 — IR 복원 켜기/끄기 두 결과 TIFF 를 남긴다.
///
/// 실행 예:
/// ```
/// NEGAFLOW_GOLDEN_DIR=/path/to/docs/verification/macos-golden/task3-grainmend \
/// NEGAFLOW_GOLDEN_INPUT=/path/to/GT-X900_frame_4.tiff \
/// NEGAFLOW_GOLDEN_INPUT_IR=/path/to/GT-X900_frame_4.tiff.ir.tiff \
/// swift test --filter MacGoldenInfraredRepairHarnessTests
/// ```
///
/// 화소 차이 분포는 두 TIFF 를 직접 비교해서 낸다(이 하네스는 파일과 검출 수치만 남긴다).
/// 두 경로 모두 **같은 평탄화 base**(RGBA16 linear CGImage)에서 출발한다 — 그래야 차이가
/// 오직 IR 복원에서만 온다. cleaned raw 합성은 앱과 같은 `CleanedRawCanvas` 를 쓴다.
/// 필름 base(Dmin)는 앱과 같이 **현상 입력마다 새로 추정**한다.
@MainActor
final class MacGoldenInfraredRepairHarnessTests: XCTestCase {

    func testEmitsInfraredRepairGolden() throws {
        guard let outputDirectory = MacGoldenAppHarness.outputDirectory() else {
            throw XCTSkip("NEGAFLOW_GOLDEN_DIR 를 지정하면 golden 을 생성합니다.")
        }
        let rawURL = try XCTUnwrap(
            MacGoldenAppHarness.inputURL("NEGAFLOW_GOLDEN_INPUT"),
            "NEGAFLOW_GOLDEN_INPUT 이 지정되지 않았습니다."
        )
        let infraredURL = try XCTUnwrap(
            MacGoldenAppHarness.inputURL("NEGAFLOW_GOLDEN_INPUT_IR"),
            "NEGAFLOW_GOLDEN_INPUT_IR 이 지정되지 않았습니다."
        )

        let engine = ChromabaseEngine()
        let rawImage = try XCTUnwrap(engine.loadScannerImage(rawURL), "raw 로드 실패")
        let infrared = try XCTUnwrap(ImageLoader.loadScannerTIFF(infraredURL), "IR 로드 실패")

        let parameters = InfraredDefectRemoval.Parameters()
        let detection: InfraredDefectRemoval.Detection
        switch InfraredDefectRemoval.detect(
            raw: rawImage, infrared: infrared, parameters: parameters
        ) {
        case .success(let result):
            detection = result
        case .failure(let failure):
            return XCTFail("IR 검출 실패: \(failure)")
        }

        let baseCG = try XCTUnwrap(
            cleanedRawContext.createCGImage(
                rawImage,
                from: rawImage.extent,
                format: .RGBA16,
                colorSpace: linearColorSpace
            ),
            "raw 평탄화 실패"
        )
        let patches = try XCTUnwrap(
            computeDefectPatches(
                .infrared(clusters: detection.clusters),
                base: baseCG,
                shouldCancel: { false }
            ),
            "IR 패치 계산 실패"
        )
        let canvas = try XCTUnwrap(
            CleanedRawCanvas(width: baseCG.width, height: baseCG.height),
            "cleaned raw 캔버스 생성 실패"
        )
        let cleanedCG = try XCTUnwrap(
            canvas.composite(base: baseCG, patches: patches.map { ($0, 1.0) }),
            "cleaned raw 합성 실패"
        )

        let options = ExportOptions(
            colorSpace: .sRGB,
            tiffCompression: .none,
            tiffBitDepth: .sixteen,
            metadataPolicy: .minimal
        )
        var exports: [[String: Any]] = []
        for (label, cgImage) in [("grainmend-off", baseCG), ("grainmend-on", cleanedCG)] {
            let input = CIImage(cgImage: cgImage, options: [.colorSpace: linearColorSpace])
            let base = try XCTUnwrap(
                engine.estimateFilmBase(in: input, mode: .auto),
                "\(label) base 추정 실패"
            )
            var params = DevelopParameters()
            params.filmType = .colorNegative
            params.developTarget = .main
            let output = outputDirectory.appendingPathComponent("\(label).tif")
            try ExportEngine.write(
                engine.developScanner(image: input, base: base, params: params),
                to: output,
                format: .tiff16,
                using: ChromabaseEngine.sharedLinearRenderContext,
                metadata: nil,
                options: options
            )
            exports.append([
                "case": label,
                "file": output.lastPathComponent,
                "sha256": try MacGoldenAppHarness.sha256(of: output),
                "bytes": try MacGoldenAppHarness.byteCount(of: output),
                "measuredBase": [
                    "r": base.rgb.x, "g": base.rgb.y, "b": base.rgb.z,
                    "source": base.source.rawValue,
                ],
            ])
        }

        let manifest: [String: Any] = [
            "task": "3 · GrainMend repair magnitude",
            "input": [
                "raw": ["path": rawURL.path, "sha256": try MacGoldenAppHarness.sha256(of: rawURL)],
                "infrared": [
                    "path": infraredURL.path,
                    "sha256": try MacGoldenAppHarness.sha256(of: infraredURL),
                ],
                "pixelWidth": baseCG.width,
                "pixelHeight": baseCG.height,
            ],
            "fixedSettings": [
                "filmType": FilmType.colorNegative.rawValue,
                "developTarget": DevelopTarget.main.rawValue,
                "look": "none (plain DevelopParameters())",
                "baseEstimationMode": "auto (현상 입력마다 재추정)",
                "exportColorSpace": "sRGB",
                "tiffBitDepth": 16,
                "tiffCompression": "none",
                "infraredSensitivity": parameters.sensitivity,
            ],
            "detection": [
                "coverage": detection.coverage,
                "coveragePercent": detection.coverage * 100,
                "candidateCount": detection.candidateCount,
                "confirmedCount": detection.confirmedCount,
                "medianGain": detection.medianGain,
                "clusterCount": detection.clusters.count,
                "offsetX": detection.offsetX,
                "offsetY": detection.offsetY,
                "alignmentStatus": detection.alignment.status.rawValue,
            ],
            "patchCount": patches.count,
            "exports": exports,
        ]
        try MacGoldenAppHarness.writeJSON(
            manifest,
            to: outputDirectory.appendingPathComponent("grainmend-repair.json")
        )
    }
}
