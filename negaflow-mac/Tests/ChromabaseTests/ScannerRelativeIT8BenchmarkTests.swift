import CryptoKit
import Foundation
import XCTest
@testable import Chromabase

final class ScannerRelativeIT8BenchmarkTests: XCTestCase {
    func testLabD50InverseRoundTripsExtendedLinearValuesWithoutClamping() {
        let samples = [
            SIMD3<Double>(1.0, 1.0, 1.0),
            SIMD3<Double>(0.18, 0.18, 0.18),
            SIMD3<Double>(-0.04, 0.32, 1.08),
            SIMD3<Double>(0.91, -0.025, 0.44),
            SIMD3<Double>(1.12, 0.24, -0.01),
        ]

        for expected in samples {
            let lab = ColorTargetColorimetry.linearSRGBToLabD50(expected)
            let actual = ColorTargetColorimetry.labD50ToLinearSRGB(lab)
            XCTAssertEqual(actual.x, expected.x, accuracy: 0.000_001, "RGB: \(expected)")
            XCTAssertEqual(actual.y, expected.y, accuracy: 0.000_001, "RGB: \(expected)")
            XCTAssertEqual(actual.z, expected.z, accuracy: 0.000_001, "RGB: \(expected)")
        }
    }

    func testBenchmarkReportsEveryPatchAndStructuralRegressionContract() throws {
        let reference = makeReferenceBytes()
        let hash = sha256(reference)
        let report = try ScannerRelativeIT8Benchmark.evaluate(
            referenceBytes: reference,
            expectedReferenceSHA256: hash
        )

        XCTAssertEqual(report.schemaVersion, 2)
        XCTAssertEqual(
            report.benchmarkKind,
            "NORITSU/FUJI roll-label aggregate relative style regression"
        )
        XCTAssertEqual(report.evidenceClass, .syntheticModel)
        XCTAssertEqual(report.qualityDecision, .notEvaluated)
        XCTAssertEqual(report.reference.sha256, hash)
        XCTAssertEqual(report.reference.patchCount, 264)
        XCTAssertEqual(report.reference.interpretedIlluminant, "D50")
        XCTAssertEqual(report.reference.interpretedObserver, "CIE1931_2deg")
        XCTAssertEqual(
            report.reference.colorimetryInterpretationProvenance,
            .benchmarkContractNotVerifiedFromReferenceHeader
        )
        XCTAssertEqual(report.syntheticModel.densityEncodingVersion, "shoulder-print-response-v4")
        XCTAssertEqual(
            report.syntheticModel.modelName,
            "bounded fixed color-negative print-response forward model"
        )
        XCTAssertEqual(
            report.syntheticModel.densityEncodingRange,
            NegativeInversion.colorResponse.normalRange,
            accuracy: 0
        )
        XCTAssertEqual(report.syntheticModel.rows, 12)
        XCTAssertEqual(report.syntheticModel.columns, 22)
        XCTAssertTrue(report.profileBundle.manifestSHA256.hasPrefix("sha256:"))
        XCTAssertEqual(
            report.profileBundle.entries.count,
            report.profileBundle.declaredProfileCount
        )
        XCTAssertTrue(report.profileBundle.entries.allSatisfy {
            $0.profileHash.hasPrefix("sha256:") && $0.fileSHA256.hasPrefix("sha256:")
        })
        XCTAssertEqual(
            report.relativeProfilePairs.map(\.filmKey),
            ["kodak ektar 100", "kodak portra 160"]
        )
        XCTAssertTrue(report.relativeProfilePairs.allSatisfy {
            $0.pairingEvidence == "normalized-roll-label-set-and-image-count-tolerance"
                && !$0.exactFramePairingProven
        })
        XCTAssertEqual(report.patches.count, 264)
        XCTAssertEqual(Set(report.patches.map(\.id)).count, 264)
        XCTAssertEqual(report.patches.map(\.id), expectedPatchIDs())

        for patch in report.patches {
            XCTAssertTrue(patch.valid, patch.id)
            XCTAssertTrue(patch.inputDeltaE00FromReference.isFinite, patch.id)
            XCTAssertLessThan(patch.inputDeltaE00FromReference, 0.001, patch.id)
            XCTAssertTrue(patch.inputLinearRGB.allChannelsFinite, patch.id)
            XCTAssertTrue(patch.syntheticNegativeTransmissionRGB.allChannelsFinite, patch.id)
            XCTAssertFalse(
                patch.inputWorkingRangeFlags.contains(.containsNonFiniteChannel),
                patch.id
            )

            for measurement in [patch.main, patch.noritsu, patch.fuji] {
                let rgb = try XCTUnwrap(measurement.linearRGB, patch.id)
                let lab = try XCTUnwrap(measurement.labD50, patch.id)
                let delta = try XCTUnwrap(measurement.deltaE00FromReference, patch.id)
                XCTAssertTrue(rgb.allChannelsFinite, patch.id)
                XCTAssertTrue(rgb.channels.allSatisfy { $0 >= -0.000_001 && $0 <= 1.000_001 }, patch.id)
                XCTAssertTrue([lab.l, lab.a, lab.b, delta].allSatisfy(\.isFinite), patch.id)
                XCTAssertFalse(
                    measurement.workingRangeFlags.contains(.containsNonFiniteChannel),
                    patch.id
                )
            }

            XCTAssertTrue(try XCTUnwrap(patch.noritsuDeltaE00FromMain, patch.id).isFinite)
            XCTAssertTrue(try XCTUnwrap(patch.fujiDeltaE00FromMain, patch.id).isFinite)
            XCTAssertTrue(try XCTUnwrap(patch.noritsuFujiDeltaE00, patch.id).isFinite)
        }

        XCTAssertEqual(report.summary.totalPatchCount, 264)
        XCTAssertEqual(report.summary.validPatchCount, 264)
        XCTAssertEqual(report.summary.nonFinitePatchCount, 0)
        XCTAssertTrue(report.summary.repeatability.mainBitExact)
        XCTAssertTrue(report.summary.repeatability.noritsuBitExact)
        XCTAssertTrue(report.summary.repeatability.fujiBitExact)
        XCTAssertTrue(report.summary.repeatability.allTargetsBitExact)
        XCTAssertEqual(report.summary.neutralTone.columnID, "16")

        for tone in [
            report.summary.neutralTone.main,
            report.summary.neutralTone.noritsu,
            report.summary.neutralTone.fuji,
        ] {
            XCTAssertEqual(tone.expectedAdjacentPairCount, 11)
            XCTAssertEqual(tone.comparedAdjacentPairCount, 11)
            XCTAssertEqual(tone.reversedAdjacentPairCount, 0)
            XCTAssertEqual(tone.exactPlateauAdjacentPairCount, 0)
            XCTAssertEqual(tone.nonFiniteAdjacentPairCount, 0)
            XCTAssertTrue(tone.strictReferenceOrderPreserved)
        }

        let extended = report.summary.extendedRange
        XCTAssertEqual(extended.inputExcursionPatchCount, 146)
        XCTAssertEqual(extended.mainExcursionDirectionPreservedPatchCount, 0)
        XCTAssertEqual(extended.noritsuExcursionDirectionPreservedPatchCount, 0)
        XCTAssertEqual(extended.fujiExcursionDirectionPreservedPatchCount, 0)

        for distribution in [
            report.summary.relativeDeltaE00.noritsuFromMain,
            report.summary.relativeDeltaE00.fujiFromMain,
            report.summary.relativeDeltaE00.noritsuFuji,
        ] {
            XCTAssertEqual(distribution.finitePatchCount, 264)
            XCTAssertTrue(try XCTUnwrap(distribution.medianDeltaE00).isFinite)
            XCTAssertTrue(try XCTUnwrap(distribution.p95DeltaE00).isFinite)
            XCTAssertTrue(try XCTUnwrap(distribution.maximumDeltaE00).isFinite)
        }
        let unitCubeCount = report.summary.relativeDeltaE00.unitCubeInputPatchCount
        XCTAssertEqual(unitCubeCount, 264 - extended.inputExcursionPatchCount)
        XCTAssertEqual(unitCubeCount, 118)
        for distribution in [
            report.summary.relativeDeltaE00.noritsuFromMainWithinUnitCube,
            report.summary.relativeDeltaE00.fujiFromMainWithinUnitCube,
            report.summary.relativeDeltaE00.noritsuFujiWithinUnitCube,
        ] {
            XCTAssertEqual(distribution.finitePatchCount, unitCubeCount)
            XCTAssertTrue(try XCTUnwrap(distribution.medianDeltaE00).isFinite)
            XCTAssertTrue(try XCTUnwrap(distribution.p95DeltaE00).isFinite)
            XCTAssertTrue(try XCTUnwrap(distribution.maximumDeltaE00).isFinite)
        }
        XCTAssertGreaterThan(
            try XCTUnwrap(report.summary.relativeDeltaE00.noritsuFromMain.maximumDeltaE00),
            0
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(report.summary.relativeDeltaE00.fujiFromMain.maximumDeltaE00),
            0
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(
                report.summary.relativeDeltaE00.noritsuFromMainWithinUnitCube.maximumDeltaE00
            ),
            0
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(
                report.summary.relativeDeltaE00.fujiFromMainWithinUnitCube.maximumDeltaE00
            ),
            0
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(
                report.summary.relativeDeltaE00.noritsuFujiWithinUnitCube.maximumDeltaE00
            ),
            0
        )

        let encoded = try JSONEncoder().encode(report)
        XCTAssertEqual(try JSONDecoder().decode(ScannerRelativeIT8BenchmarkReport.self, from: encoded), report)

        printNumericSummary(report)
    }

    func testReferenceHashMismatchStopsBeforeEvaluation() {
        let reference = makeReferenceBytes()
        let wrongHash = sha256(Data("different reference".utf8))

        XCTAssertThrowsError(try ScannerRelativeIT8Benchmark.evaluate(
            referenceBytes: reference,
            expectedReferenceSHA256: wrongHash
        )) { error in
            guard case let ScannerRelativeIT8BenchmarkError.referenceSHA256Mismatch(expected, actual) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(expected, wrongHash)
            XCTAssertEqual(actual, self.sha256(reference))
        }
    }

    func testReferenceMustContainExactlyA1ThroughL22() {
        let incomplete = makeReferenceBytes(omitting: "L22")

        XCTAssertThrowsError(try ScannerRelativeIT8Benchmark.evaluate(
            referenceBytes: incomplete,
            expectedReferenceSHA256: sha256(incomplete)
        )) { error in
            XCTAssertEqual(
                error as? ScannerRelativeIT8BenchmarkError,
                .invalidReferencePatchCount(expected: 264, actual: 263)
            )
        }
    }

    private func makeReferenceBytes(omitting omittedID: String? = nil) -> Data {
        var rows: [String] = []
        rows.reserveCapacity(264)
        for row in 0..<12 {
            for column in 0..<22 {
                let id = patchID(row: row, column: column)
                guard id != omittedID else { continue }
                let lab = referenceLab(row: row, column: column)
                rows.append(String(
                    format: "%@ %.12f %.12f %.12f",
                    locale: Locale(identifier: "en_US_POSIX"),
                    id,
                    lab.l,
                    lab.a,
                    lab.b
                ))
            }
        }
        let source = """
        IT8.7/1
        ORIGINATOR "negaflow syntheticModel test"
        DESCRIPTOR "No physical device accuracy claim"
        NUMBER_OF_FIELDS 4
        BEGIN_DATA_FORMAT
        SAMPLE_ID LAB_L LAB_A LAB_B
        END_DATA_FORMAT
        NUMBER_OF_SETS \(rows.count)
        BEGIN_DATA
        \(rows.joined(separator: "\n"))
        END_DATA
        """
        return Data(source.utf8)
    }

    private func referenceLab(row: Int, column: Int) -> ColorTargetLab {
        if column == 15 {
            return ColorTargetLab(
                l: 90.0 - 85.0 * Double(row) / 11.0,
                a: 0,
                b: 0
            )
        }
        let lightness = 18.0 + 70.0 * Double(column) / 21.0
        let hue = 2.0 * Double.pi * (
            Double(row) / 11.0 + Double(column) * 0.013
        )
        let chroma = 42.0 + 38.0 * (0.5 + 0.5 * sin(Double(column) * 0.67))
        return ColorTargetLab(
            l: lightness,
            a: chroma * cos(hue),
            b: chroma * sin(hue)
        )
    }

    private func expectedPatchIDs() -> [String] {
        (0..<12).flatMap { row in
            (0..<22).map { patchID(row: row, column: $0) }
        }
    }

    private func patchID(row: Int, column: Int) -> String {
        String(UnicodeScalar(65 + row)!) + String(column + 1)
    }

    private func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "sha256:\(digest)"
    }

    private func printNumericSummary(_ report: ScannerRelativeIT8BenchmarkReport) {
        let noritsu = report.summary.relativeDeltaE00.noritsuFromMain
        let fuji = report.summary.relativeDeltaE00.fujiFromMain
        let between = report.summary.relativeDeltaE00.noritsuFuji
        let noritsuCube = report.summary.relativeDeltaE00.noritsuFromMainWithinUnitCube
        let fujiCube = report.summary.relativeDeltaE00.fujiFromMainWithinUnitCube
        let betweenCube = report.summary.relativeDeltaE00.noritsuFujiWithinUnitCube
        print(String(
            format: "[scanner-relative-it8] valid=%d/%d extended=%d repeatable=%@ "
                + "NOR-MAIN median/p95/max=%.6f/%.6f/%.6f "
                + "FUJI-MAIN median/p95/max=%.6f/%.6f/%.6f "
                + "NOR-FUJI median/p95/max=%.6f/%.6f/%.6f "
                + "unitCube=%d NOR-MAIN=%.6f/%.6f/%.6f "
                + "FUJI-MAIN=%.6f/%.6f/%.6f NOR-FUJI=%.6f/%.6f/%.6f",
            report.summary.validPatchCount,
            report.summary.totalPatchCount,
            report.summary.extendedRange.inputExcursionPatchCount,
            report.summary.repeatability.allTargetsBitExact ? "true" : "false",
            noritsu.medianDeltaE00 ?? .nan,
            noritsu.p95DeltaE00 ?? .nan,
            noritsu.maximumDeltaE00 ?? .nan,
            fuji.medianDeltaE00 ?? .nan,
            fuji.p95DeltaE00 ?? .nan,
            fuji.maximumDeltaE00 ?? .nan,
            between.medianDeltaE00 ?? .nan,
            between.p95DeltaE00 ?? .nan,
            between.maximumDeltaE00 ?? .nan,
            report.summary.relativeDeltaE00.unitCubeInputPatchCount,
            noritsuCube.medianDeltaE00 ?? .nan,
            noritsuCube.p95DeltaE00 ?? .nan,
            noritsuCube.maximumDeltaE00 ?? .nan,
            fujiCube.medianDeltaE00 ?? .nan,
            fujiCube.p95DeltaE00 ?? .nan,
            fujiCube.maximumDeltaE00 ?? .nan,
            betweenCube.medianDeltaE00 ?? .nan,
            betweenCube.p95DeltaE00 ?? .nan,
            betweenCube.maximumDeltaE00 ?? .nan
        ))
    }

}

private extension ScannerRelativeIT8BenchmarkReport.RGB {
    var allChannelsFinite: Bool { r.isFinite && g.isFinite && b.isFinite }
    var channels: [Double] { [r, g, b] }
}
