import XCTest
import CoreImage
@testable import Chromabase

final class FilmBaseMeasurementDiagnosticsTests: XCTestCase {
    func testMeasuredEvidenceDistinguishesCleanAndChannelInconsistentBorders() throws {
        // 2026-07-14 v3: 연결 성분 검출이 1차 경로 — 깨끗한 보더는 성분으로 잡힌다.
        let clean = try XCTUnwrap(FilmBaseEstimator.estimate(from: fixture()))
        let cleanDiagnostics = try XCTUnwrap(clean.measurementDiagnostics)
        XCTAssertEqual(clean.source, .auto)
        XCTAssertEqual(cleanDiagnostics.method, .connectedComponent)
        XCTAssertGreaterThan(cleanDiagnostics.sampleCoverage, 0)
        XCTAssertGreaterThan(cleanDiagnostics.spatialCoverage, 0.65)
        XCTAssertFalse(cleanDiagnostics.anomalies.contains(.inconsistentChannels))
        XCTAssertFalse(cleanDiagnostics.isCalibratedProbability)

        // 채널 불일치 증거 채점은 빌더 단위로 검증한다(채점은 선택 표본만 보므로 방법과 무관).
        func samples(_ color: (Int) -> SIMD3<Double>) -> [FilmBaseSample] {
            (0..<64).map { FilmBaseSample(x: $0 % 16, y: $0 / 16, color: color($0)) }
        }
        let cleanMeasurement = try XCTUnwrap(FilmBaseMeasurementBuilder.build(
            method: .continuousBorder, sampledPixelCount: 1600, candidateCount: 64,
            selected: samples { _ in SIMD3(0.72, 0.52, 0.34) }, gridWidth: 16, gridHeight: 4
        ))
        let mixedMeasurement = try XCTUnwrap(FilmBaseMeasurementBuilder.build(
            method: .continuousBorder, sampledPixelCount: 1600, candidateCount: 64,
            selected: samples {
                $0.isMultiple(of: 2) ? SIMD3(0.80, 0.45, 0.33) : SIMD3(0.66, 0.58, 0.34)
            }, gridWidth: 16, gridHeight: 4
        ))
        XCTAssertGreaterThan(cleanMeasurement.diagnostics.evidenceScore,
                             mixedMeasurement.diagnostics.evidenceScore)
        XCTAssertLessThan(cleanMeasurement.diagnostics.chromaticityMAD,
                          mixedMeasurement.diagnostics.chromaticityMAD)
        XCTAssertFalse(cleanMeasurement.diagnostics.anomalies.contains(.inconsistentChannels))
        XCTAssertTrue(mixedMeasurement.diagnostics.anomalies.contains(.inconsistentChannels))
    }

    func testClippedBorderLowersEvidenceAndRecordsAnomaly() throws {
        let clipped = try XCTUnwrap(FilmBaseEstimator.estimate(from: fixture { _, _ in
            SIMD3(1.0, 0.55, 0.20)
        }))
        let diagnostics = try XCTUnwrap(clipped.measurementDiagnostics)

        XCTAssertEqual(diagnostics.clippedFraction, 1, accuracy: 0.0001)
        XCTAssertEqual(diagnostics.evidenceComponents.unclippedSamples, 0, accuracy: 0.0001)
        XCTAssertEqual(diagnostics.evidenceScore, 0, accuracy: 0.0001)
        XCTAssertTrue(diagnostics.anomalies.contains(.clippedSamples))
    }

    func testSidecarCarriesMeasuredEvidenceAndDoesNotInventManualConfidence() throws {
        let automatic = try XCTUnwrap(FilmBaseEstimator.estimate(from: fixture()))
        let automaticSidecar = Sidecar.FilmBaseDiagnostics(automatic)
        let manualSidecar = Sidecar.FilmBaseDiagnostics(
            FilmBase(rgb: SIMD3(0.72, 0.52, 0.34), source: .manual)
        )

        XCTAssertEqual(automaticSidecar.confidence, automatic.measurementDiagnostics?.evidenceScore)
        XCTAssertEqual(automaticSidecar.confidenceBasis, "measuredEvidenceScoreV1")
        XCTAssertEqual(automaticSidecar.confidenceIsCalibratedProbability, false)
        XCTAssertGreaterThan(automaticSidecar.measurement?.sampledPixelCount ?? 0, 0)
        XCTAssertNil(manualSidecar.confidence)
        XCTAssertNil(manualSidecar.confidenceBasis)
        XCTAssertNil(manualSidecar.measurement)

        let data = try JSONEncoder().encode(automaticSidecar)
        let decoded = try JSONDecoder().decode(Sidecar.FilmBaseDiagnostics.self, from: data)
        XCTAssertEqual(decoded.measurement, automatic.measurementDiagnostics)
        XCTAssertEqual(decoded.confidence, automatic.measurementDiagnostics?.evidenceScore)
    }

    func testFilmBaseDecodesLegacyPayloadWithoutMeasurementDiagnostics() throws {
        struct LegacyFilmBase: Encodable {
            let rgb: SIMD3<Double>
            let source: FilmBase.Source
        }
        let data = try JSONEncoder().encode(LegacyFilmBase(
            rgb: SIMD3(0.72, 0.52, 0.34),
            source: .border
        ))

        let decoded = try JSONDecoder().decode(FilmBase.self, from: data)
        XCTAssertEqual(decoded.rgb, SIMD3(0.72, 0.52, 0.34))
        XCTAssertEqual(decoded.source, .border)
        XCTAssertNil(decoded.measurementDiagnostics)
    }

    private func fixture(
        borderColor: (_ x: Int, _ y: Int) -> SIMD3<Double> = { _, _ in
            SIMD3(0.72, 0.52, 0.34)
        }
    ) -> CIImage {
        let width = 160
        let height = 100
        let borderHeight = 10
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let color = y < borderHeight
                    ? borderColor(x, y)
                    : SIMD3<Double>(0.12, 0.07, 0.04)
                let offset = (y * width + x) * 4
                pixels[offset] = Float(color.x)
                pixels[offset + 1] = Float(color.y)
                pixels[offset + 2] = Float(color.z)
                pixels[offset + 3] = 1
            }
        }
        return CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
    }
}
