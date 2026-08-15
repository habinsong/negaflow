import CoreImage
import Foundation
import XCTest
@testable import Chromabase

/// [작업 2] 적외선 정렬 상관값 — 같은 스캔의 RGB + IR 쌍으로 검출을 돌리고 진단값을 남긴다.
///
/// 실행 예:
/// ```
/// NEGAFLOW_GOLDEN_DIR=/path/to/docs/verification/macos-golden/task2-infrared \
/// NEGAFLOW_GOLDEN_INPUT=/path/to/GT-X900_frame_4.tiff \
/// NEGAFLOW_GOLDEN_INPUT_IR=/path/to/GT-X900_frame_4.tiff.ir.tiff \
/// swift test --filter MacGoldenInfraredAlignmentHarnessTests
/// ```
///
/// 정합 경로가 둘(결함 신호 → 누설 상관)이라 `peakCorrelation` 의 의미가 경로마다 다르다.
/// 어느 경로가 답을 냈는지 구분할 수 있게 두 추정기를 각각 따로 호출한 값도 함께 적는다.
final class MacGoldenInfraredAlignmentHarnessTests: XCTestCase {

    func testEmitsInfraredAlignmentGolden() throws {
        guard let outputDirectory = MacGoldenHarness.outputDirectory() else {
            throw XCTSkip("NEGAFLOW_GOLDEN_DIR 를 지정하면 golden 을 생성합니다.")
        }
        let rawURL = try XCTUnwrap(
            MacGoldenHarness.inputURL("NEGAFLOW_GOLDEN_INPUT"),
            "NEGAFLOW_GOLDEN_INPUT 이 지정되지 않았습니다."
        )
        let infraredURL = try XCTUnwrap(
            MacGoldenHarness.inputURL("NEGAFLOW_GOLDEN_INPUT_IR"),
            "NEGAFLOW_GOLDEN_INPUT_IR 이 지정되지 않았습니다."
        )

        let engine = ChromabaseEngine()
        let raw = try XCTUnwrap(engine.loadScannerImage(rawURL), "raw 로드 실패")
        let infrared = try XCTUnwrap(ImageLoader.loadScannerTIFF(infraredURL), "IR 로드 실패")
        let extent = raw.extent.integral
        let width = Int(extent.width), height = Int(extent.height)

        let parameters = InfraredDefectRemoval.Parameters()
        let redPlane = try XCTUnwrap(
            InfraredDefectRemoval.renderRedPlane(
                raw.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)),
                width: width, height: height
            )
        )
        let irExtent = infrared.extent.integral
        let irPlane = try XCTUnwrap(
            InfraredDefectRemoval.renderRedPlane(
                infrared.transformed(
                    by: CGAffineTransform(translationX: -irExtent.minX, y: -irExtent.minY)
                ),
                width: width, height: height
            )
        )

        // 1순위 경로(결함 신호)를 단독으로 호출한다 — nil 이면 누설 상관으로 내려간 것이다.
        let defectAlignment = InfraredDefectRemoval.estimateDefectAlignment(
            infrared: irPlane, red: redPlane,
            width: width, height: height,
            searchRadius: parameters.alignmentSearchRadius
        )
        // 실제 검출이 쓰는 통합 추정기.
        let alignment = InfraredDefectRemoval.estimateAlignment(
            infrared: irPlane, red: redPlane,
            width: width, height: height,
            searchRadius: parameters.alignmentSearchRadius
        )

        let started = Date()
        let outcome = InfraredDefectRemoval.detect(
            raw: raw, infrared: infrared, parameters: parameters
        )
        let elapsed = Date().timeIntervalSince(started)

        var detection: [String: Any] = ["elapsedSeconds": elapsed]
        switch outcome {
        case .success(let result):
            detection["result"] = "success"
            detection["coveragePercent"] = result.coverage * 100
            detection["coverage"] = result.coverage
            detection["offsetX"] = result.offsetX
            detection["offsetY"] = result.offsetY
            detection["candidateCount"] = result.candidateCount
            detection["confirmedCount"] = result.confirmedCount
            detection["medianGain"] = result.medianGain
            detection["clusterCount"] = result.clusters.count
            detection["componentCount"] = result.components.count
            detection["alignment"] = Self.encode(result.alignment)
        case .failure(let failure):
            detection["result"] = "failure"
            detection["failure"] = String(describing: failure)
        }

        let manifest: [String: Any] = [
            "task": "2 · infrared alignment correlation",
            "input": [
                "raw": ["path": rawURL.path, "sha256": try MacGoldenHarness.sha256(of: rawURL)],
                "infrared": [
                    "path": infraredURL.path,
                    "sha256": try MacGoldenHarness.sha256(of: infraredURL),
                ],
                "pixelWidth": width,
                "pixelHeight": height,
            ],
            "parameters": [
                "sensitivity": parameters.sensitivity,
                "dilateRadius": parameters.dilateRadius,
                "minArea": parameters.minArea,
                "maxCoverage": parameters.maxCoverage,
                "alignmentSearchRadius": parameters.alignmentSearchRadius,
                "clusterTile": parameters.clusterTile,
                "clusterPadding": parameters.clusterPadding,
            ],
            "estimateDefectAlignment": defectAlignment.map {
                [
                    "offsetX": $0.offsetX,
                    "offsetY": $0.offsetY,
                    "peak": $0.peak,
                    "runnerUp": $0.runnerUp,
                    "peakOverRunnerUp": $0.runnerUp > 0 ? $0.peak / $0.runnerUp : NSNull(),
                    "pointCount": $0.pointCount,
                    "atSearchLimit": $0.atSearchLimit,
                ] as [String: Any]
            } ?? ["result": "nil (결함 신호 부족 → 누설 상관 경로)"],
            "estimateAlignment": Self.encode(alignment),
            "detect": detection,
        ]
        try MacGoldenHarness.writeJSON(
            manifest,
            to: outputDirectory.appendingPathComponent("infrared-alignment.json")
        )
    }

    private static func encode(
        _ diagnostics: InfraredDefectRemoval.AlignmentDiagnostics
    ) -> [String: Any] {
        [
            "status": diagnostics.status.rawValue,
            "offsetX": diagnostics.offsetX,
            "offsetY": diagnostics.offsetY,
            "peakCorrelation": diagnostics.peakCorrelation.map { $0 as Any } ?? NSNull(),
            "runnerUpCorrelation": diagnostics.runnerUpCorrelation.map { $0 as Any } ?? NSNull(),
            "searchRadius": diagnostics.searchRadius,
            "downsampleFactor": diagnostics.downsampleFactor,
            "isAccepted": diagnostics.isAccepted,
        ]
    }
}
