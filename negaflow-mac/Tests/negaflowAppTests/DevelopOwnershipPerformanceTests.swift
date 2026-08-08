import Foundation
import XCTest
import Chromabase
@testable import negaflowApp

@MainActor
final class DevelopOwnershipPerformanceTests: XCTestCase {
    private static let frameCounts = [1_000, 10_000, 50_000]
    private static let warmupIterations = 100
    private static let measurementIterations = 20
    private static let lookupsPerMeasurement = 100

    func testFrameOwnershipLookupPerformanceWhenEnabled() throws {
        guard ProcessInfo.processInfo.environment["NEGAFLOW_OWNERSHIP_PERF"] == "1" else {
            throw XCTSkip("Set NEGAFLOW_OWNERSHIP_PERF=1 to run the ownership benchmark.")
        }

        var cases: [OwnershipBenchmarkCase] = []
        for frameCount in Self.frameCounts {
            let model = AppModel()
            let frames = Self.makeFrames(count: frameCount)
            model.frames = frames
            model.sourceAvailabilityRefreshTask?.cancel()
            model.sourceAvailabilityRefreshTask = nil
            let target = try XCTUnwrap(frames.last)

            for _ in 0..<Self.warmupIterations {
                XCTAssertTrue(model.ownsFrame(target))
            }

            let clock = ContinuousClock()
            var samples: [Double] = []
            var matchCount = 0
            for _ in 0..<Self.measurementIterations {
                let started = clock.now
                for _ in 0..<Self.lookupsPerMeasurement where model.ownsFrame(target) {
                    matchCount += 1
                }
                let nanoseconds = Self.nanoseconds(started.duration(to: clock.now))
                samples.append(nanoseconds / Double(Self.lookupsPerMeasurement))
            }
            XCTAssertEqual(
                matchCount,
                Self.measurementIterations * Self.lookupsPerMeasurement
            )
            let sorted = samples.sorted()
            cases.append(OwnershipBenchmarkCase(
                frameCount: frameCount,
                lookupsPerMeasurement: Self.lookupsPerMeasurement,
                samplesNanosecondsPerLookup: samples,
                p50NanosecondsPerLookup: Self.percentile(sorted, percentile: 0.50),
                p95NanosecondsPerLookup: Self.percentile(sorted, percentile: 0.95)
            ))
            model.frames = []
        }

        try Self.writeReportIfRequested(OwnershipBenchmarkReport(
            configuration: Self.buildConfiguration,
            warmupIterations: Self.warmupIterations,
            measurementIterations: Self.measurementIterations,
            cases: cases
        ))
    }

    private static func makeFrames(count: Int) -> [ScanFrame] {
        (0..<count).map { index in
            let suffix = String(format: "%012llx", UInt64(index + 1))
            return ScanFrame(
                scanIndex: index + 1,
                rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-owner-\(suffix).tiff"),
                filmType: .colorNegative,
                id: UUID(uuidString: "00000000-0000-4000-8000-\(suffix)")!
            )
        }
    }

    private static func nanoseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000_000_000
            + Double(components.attoseconds) / 1_000_000_000
    }

    private static func percentile(_ sorted: [Double], percentile: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = max(1, Int(ceil(percentile * Double(sorted.count))))
        return sorted[min(rank - 1, sorted.count - 1)]
    }

    private static func writeReportIfRequested(_ report: OwnershipBenchmarkReport) throws {
        guard let path = ProcessInfo.processInfo.environment["NEGAFLOW_OWNERSHIP_PERF_REPORT"],
              !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: url, options: .atomic)
    }

    private static var buildConfiguration: String {
        #if DEBUG
        "debug"
        #else
        "release"
        #endif
    }
}

private struct OwnershipBenchmarkReport: Encodable {
    let configuration: String
    let warmupIterations: Int
    let measurementIterations: Int
    let cases: [OwnershipBenchmarkCase]
}

private struct OwnershipBenchmarkCase: Encodable {
    let frameCount: Int
    let lookupsPerMeasurement: Int
    let samplesNanosecondsPerLookup: [Double]
    let p50NanosecondsPerLookup: Double
    let p95NanosecondsPerLookup: Double
}
