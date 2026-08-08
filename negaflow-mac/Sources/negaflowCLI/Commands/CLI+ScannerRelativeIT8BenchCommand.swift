import Chromabase
import Foundation

extension CLI {
    func scannerRelativeIT8Bench() async throws {
        guard args.count > 4 else {
            fail(
                "usage: negaflow scanner-relative-it8-bench <reference.txt> "
                    + "--sha256 sha256:<64 lowercase hex> [--out report.json]"
            )
        }

        let referenceURL = URL(fileURLWithPath: args[2])
        var expectedSHA256: String?
        var outputURL: URL?
        var index = 3
        while index < args.count {
            let option = args[index]
            guard ["--sha256", "--out"].contains(option), index + 1 < args.count else {
                fail("unknown or incomplete scanner-relative-it8-bench option: \(option)")
            }
            let value = args[index + 1]
            guard !value.hasPrefix("--") else {
                fail("missing value for scanner-relative-it8-bench option: \(option)")
            }
            switch option {
            case "--sha256":
                guard expectedSHA256 == nil else {
                    fail("duplicate scanner-relative-it8-bench option: --sha256")
                }
                expectedSHA256 = value
            case "--out":
                guard outputURL == nil else {
                    fail("duplicate scanner-relative-it8-bench option: --out")
                }
                outputURL = URL(fileURLWithPath: value)
            default:
                preconditionFailure("validated option was not handled")
            }
            index += 2
        }

        guard let expectedSHA256 else {
            fail("scanner-relative-it8-bench requires --sha256")
        }
        let referenceBytes = try Data(contentsOf: referenceURL, options: [.mappedIfSafe])
        let report = try ScannerRelativeIT8Benchmark.evaluate(
            referenceBytes: referenceBytes,
            expectedReferenceSHA256: expectedSHA256
        )
        let destination = outputURL ?? referenceURL.deletingLastPathComponent().appendingPathComponent(
            referenceURL.deletingPathExtension().lastPathComponent + ".scanner-relative-report.json"
        )
        guard canonicalScannerIT8URL(destination) != canonicalScannerIT8URL(referenceURL) else {
            fail("--out must not overwrite the reference file")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: destination, options: .atomic)

        let relative = report.summary.relativeDeltaE00
        print("[scanner-relative-it8] report: \(destination.path)")
        print(
            "[scanner-relative-it8] evidence=\(report.evidenceClass.rawValue) "
                + "qualityDecision=\(report.qualityDecision.rawValue) "
                + "valid=\(report.summary.validPatchCount)/\(report.summary.totalPatchCount) "
                + "repeatable=\(report.summary.repeatability.allTargetsBitExact)"
        )
        print(
            "[scanner-relative-it8] profile-manifest=\(report.profileBundle.manifestSHA256) "
                + "pairs=\(report.relativeProfilePairs.map(\.filmKey).joined(separator: ","))"
        )
        print(
            "[scanner-relative-it8] unit-cube=\(relative.unitCubeInputPatchCount) "
                + "NOR-MAIN=\(formatScannerIT8Distribution(relative.noritsuFromMainWithinUnitCube)) "
                + "FUJI-MAIN=\(formatScannerIT8Distribution(relative.fujiFromMainWithinUnitCube)) "
                + "NOR-FUJI=\(formatScannerIT8Distribution(relative.noritsuFujiWithinUnitCube))"
        )
    }

    private func formatScannerIT8Distribution(
        _ value: ScannerRelativeIT8BenchmarkReport.DeltaDistribution
    ) -> String {
        String(
            format: "median/p95/max=%.6f/%.6f/%.6f",
            value.medianDeltaE00 ?? .nan,
            value.p95DeltaE00 ?? .nan,
            value.maximumDeltaE00 ?? .nan
        )
    }

    private func canonicalScannerIT8URL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
