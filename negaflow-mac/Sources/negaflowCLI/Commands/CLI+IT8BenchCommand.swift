import Chromabase
import Foundation

extension CLI {
    func it8Bench() async throws {
        guard args.count > 2 else {
            fail("usage: negaflow it8-bench <manifest.json> [--image path] [--reference path] [--out report.json]")
        }

        let manifestURL = URL(fileURLWithPath: args[2])
        var imageURL: URL?
        var referenceURL: URL?
        var outputURL: URL?
        var index = 3
        while index < args.count {
            let option = args[index]
            guard ["--image", "--reference", "--out"].contains(option),
                  index + 1 < args.count else {
                fail("unknown or incomplete it8-bench option: \(option)")
            }
            let value = args[index + 1]
            guard !value.hasPrefix("--") else {
                fail("missing value for it8-bench option: \(option)")
            }
            switch option {
            case "--image":
                guard imageURL == nil else { fail("duplicate it8-bench option: --image") }
                imageURL = URL(fileURLWithPath: value)
            case "--reference":
                guard referenceURL == nil else { fail("duplicate it8-bench option: --reference") }
                referenceURL = URL(fileURLWithPath: value)
            case "--out":
                guard outputURL == nil else { fail("duplicate it8-bench option: --out") }
                outputURL = URL(fileURLWithPath: value)
            default:
                preconditionFailure("validated option was not handled")
            }
            index += 2
        }

        let report = try IT8PatchEvaluator.evaluate(
            manifestURL: manifestURL,
            imageURLOverride: imageURL,
            referenceURLOverride: referenceURL
        )
        let destination = outputURL ?? manifestURL.deletingLastPathComponent().appendingPathComponent(
            manifestURL.deletingPathExtension().lastPathComponent + ".report.json"
        )
        let protectedInputs = [
            manifestURL,
            URL(fileURLWithPath: report.image.path),
            URL(fileURLWithPath: report.reference.path),
        ].map(canonicalIT8FileURL)
        guard !protectedInputs.contains(canonicalIT8FileURL(destination)) else {
            fail("--out must not overwrite the manifest, image, or reference file")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: destination, options: .atomic)

        let nonFinitePatchCount = report.patches.reduce(into: 0) { count, patch in
            if patch.flags.contains(.containsNonFiniteValue) { count += 1 }
        }
        print("[it8-bench] report: \(destination.path)")
        print("[it8-bench] target=\(report.targetStandard) batch=\(report.batchID) evidence=\(report.evidenceClass.rawValue)")
        print(
            "[it8-bench] valid=\(report.summary.validPatchCount)/\(report.patches.count) "
                + "nonfinite-patches=\(nonFinitePatchCount) "
                + "median-DeltaE00=\(formatIT8Metric(report.summary.medianDeltaE00)) "
                + "p95-DeltaE00=\(formatIT8Metric(report.summary.p95DeltaE00)) "
                + "max-DeltaE00=\(formatIT8Metric(report.summary.maximumDeltaE00)) "
                + "working-space-excursion-patches=\(report.summary.workingSpaceExcursionPatchCount) "
                + "source-code-clipping=\(report.sourceCodeEndpointClipping.rawValue) "
                + "qualityDecision=\(report.qualityDecision.rawValue)"
        )
    }

    private func formatIT8Metric(_ value: Double?) -> String {
        value.map { String(format: "%.4f", $0) } ?? "n/a"
    }

    private func canonicalIT8FileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
