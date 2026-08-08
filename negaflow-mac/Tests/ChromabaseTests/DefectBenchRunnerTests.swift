import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

// 골든셋 벤치 러너 검증 — 합성 이미지로 아티팩트(before/after/diff/mask/crop)와 리포트 산출을
// 확인한다. 실제 스캔 골든셋 QA 는 사람이 CLI(`negaflow defect-bench`)로 수행한다.
final class DefectBenchRunnerTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

    func testBenchProducesArtifactsAndReport() throws {
        let w = 320, h = 240, base = 120
        var px = [UInt8](repeating: 255, count: w * h * 4)
        var seed: UInt64 = 0xBE7C4
        for i in 0..<(w * h) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let grain = Int(seed >> 41) % 7 - 3
            let o = i * 4
            let v = UInt8(max(0, min(255, base + grain)))
            px[o] = v; px[o + 1] = v; px[o + 2] = v; px[o + 3] = 255
        }
        // 결함: 가로 스크래치 + 먼지 점 2개.
        for x in 40..<240 { let o = (120 * w + x) * 4; px[o] = 195; px[o + 1] = 195; px[o + 2] = 195 }
        for (cx, cy) in [(80, 60), (240, 180)] {
            for yy in (cy - 2)...(cy + 2) {
                for xx in (cx - 2)...(cx + 2) {
                    let o = (yy * w + xx) * 4
                    px[o] = 30; px[o + 1] = 30; px[o + 2] = 30
                }
            }
        }
        let image = CIImage(bitmapData: Data(px), bytesPerRow: w * 4,
                            size: CGSize(width: w, height: h), format: .RGBA8, colorSpace: linear)

        let outDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("defect-bench-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outDir) }

        let entry = try DefectBenchRunner.run(image: image, name: "synthetic", outputDir: outDir,
                                           sensitivity: 3.0, cropCount: 4, cropSize: 96)
        XCTAssertGreaterThanOrEqual(entry.defectTotal, 2, "스크래치+먼지가 검출되어야 한다")
        XCTAssertGreaterThan(entry.changedPixelCount, 0, "복원으로 픽셀이 바뀌어야 한다")
        XCTAssertLessThan(entry.changedPixelFraction, 0.10, "과잉 수정(광역 와이프) 금지")
        XCTAssertGreaterThan(entry.candidatePixelFraction, 0)
        XCTAssertFalse(entry.automaticFalsePositiveRisk)
        XCTAssertGreaterThan(entry.meanConfidence, 0.2)
        XCTAssertGreaterThan(entry.detectMilliseconds, 0)

        // 아티팩트 파일이 실제로 존재해야 한다.
        let fm = FileManager.default
        for suffix in ["before", "after", "diff", "mask"] {
            let file = outDir.appendingPathComponent("synthetic-\(suffix).png")
            XCTAssertTrue(fm.fileExists(atPath: file.path), "\(suffix).png 누락")
        }
        let cropFiles = entry.artifacts.filter { $0.contains("-crop") }
        XCTAssertFalse(cropFiles.isEmpty, "100% crop 스트립이 생성되어야 한다")
        for file in cropFiles {
            XCTAssertTrue(fm.fileExists(atPath: outDir.appendingPathComponent(file).path))
        }

        // 리포트(JSON 라운드트립 + md 생성).
        try DefectBenchRunner.writeReport([entry], to: outDir)
        let jsonURL = outDir.appendingPathComponent("report.json")
        XCTAssertTrue(fm.fileExists(atPath: jsonURL.path))
        let decoded = try JSONDecoder().decode([DefectBenchEntry].self, from: Data(contentsOf: jsonURL))
        XCTAssertEqual(decoded.first?.imageName, "synthetic")
        XCTAssertEqual(decoded.first?.defectTotal, entry.defectTotal)
        XCTAssertTrue(fm.fileExists(atPath: outDir.appendingPathComponent("report.md").path))
    }

    func testReferenceMetricsReportImprovementAndRegressionWithoutQualityGate() throws {
        let reference: [UInt8] = [
            100, 100, 100, 255,
            100, 100, 100, 255,
        ]
        let before: [UInt8] = [
            110, 110, 110, 255,
            110, 110, 110, 255,
        ]
        let after: [UInt8] = [
            105, 105, 105, 255,
            120, 120, 120, 255,
        ]

        let metrics = try DefectBenchReferenceEvaluator.evaluate(
            before: before,
            after: after,
            reference: reference,
            width: 2,
            height: 1,
            referenceName: "manual-restoration.png"
        )

        XCTAssertEqual(metrics.referenceName, "manual-restoration.png")
        XCTAssertEqual(metrics.improvedPixelFraction, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(metrics.regressedPixelFraction, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(metrics.baselineMeanAbsoluteError, 10.0 / 255.0, accuracy: 0.000_001)
        XCTAssertEqual(metrics.repairedMeanAbsoluteError, 12.5 / 255.0, accuracy: 0.000_001)
        XCTAssertLessThan(metrics.psnrDelta ?? 0, 0)
    }

    func testReferenceMetricsRejectMismatchedBuffers() {
        XCTAssertThrowsError(try DefectBenchReferenceEvaluator.evaluate(
            before: [0, 0, 0, 255],
            after: [0, 0, 0, 255],
            reference: [],
            width: 1,
            height: 1,
            referenceName: "missing.png"
        ))
    }

    func testMetricsOnlyReportDoesNotClaimMissingArtifactsExist() throws {
        let outDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("defect-bench-metrics-report-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outDir) }
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let entry = DefectBenchEntry(
            imageName: "metrics-only",
            width: 8,
            height: 8,
            sensitivity: 6,
            detectMilliseconds: 1,
            repairMilliseconds: 1,
            defectCounts: [:],
            defectTotal: 0,
            meanConfidence: 0,
            candidatePixelFraction: 0,
            automaticFalsePositiveRisk: false,
            changedPixelCount: 0,
            changedPixelFraction: 0,
            meanChangedDelta: 0,
            artifacts: [],
            referenceMetrics: nil
        )

        try DefectBenchRunner.writeReport([entry], to: outDir)
        let markdown = try String(
            contentsOf: outDir.appendingPathComponent("report.md"),
            encoding: .utf8
        )

        XCTAssertTrue(markdown.contains("metrics-only"))
        XCTAssertFalse(markdown.contains("-before/-after"))
    }
}
