import Foundation
import XCTest
import Chromabase
@testable import negaflowApp

@MainActor
final class LibraryCatalogPerformanceTests: XCTestCase {
    func testWholeCatalogJSONPerformanceWhenEnabled() throws {
        guard ProcessInfo.processInfo.environment["NEGAFLOW_CATALOG_PERF"] == "1" else {
            throw XCTSkip(
                "Set NEGAFLOW_CATALOG_PERF=1 to run the whole-catalog JSON benchmark."
            )
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-catalog-benchmark-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var cases: [LibraryCatalogBenchmarkSupport.CaseReport] = []
        for frameCount in Self.frameCounts {
            let catalog = Self.makeCatalog(frameCount: frameCount)
            let encoded = try XCTUnwrap(LibraryCatalogFile.encode(catalog))
            let expected = Self.outcome(catalog, payloadBytes: encoded.count)
            let iterations = frameCount >= 50_000 ? 3 : 5

            cases.append(try LibraryCatalogBenchmarkSupport.measure(
                scenario: "json-encode",
                frameCount: frameCount,
                measurementIterations: iterations
            ) {
                let data = try XCTUnwrap(LibraryCatalogFile.encode(catalog))
                return Self.outcome(catalog, payloadBytes: data.count)
            })

            cases.append(try LibraryCatalogBenchmarkSupport.measure(
                scenario: "json-decode",
                frameCount: frameCount,
                measurementIterations: iterations
            ) {
                let decoded = try XCTUnwrap(LibraryCatalogFile.decode(encoded))
                return Self.outcome(decoded, payloadBytes: encoded.count)
            })

            let primary = root.appendingPathComponent("catalog-\(frameCount).json")
            cases.append(try LibraryCatalogBenchmarkSupport.measure(
                scenario: "atomic-write-new-primary",
                frameCount: frameCount,
                measurementIterations: iterations,
                prepare: {
                    try? FileManager.default.removeItem(at: primary)
                    try? FileManager.default.removeItem(at: LibraryCatalogFile.backupURL(for: primary))
                }
            ) {
                guard LibraryCatalogFile.write(encoded, to: primary) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let bytes = try Self.fileSize(primary)
                return Self.outcome(catalog, payloadBytes: bytes)
            })

            try encoded.write(to: primary, options: .atomic)
            cases.append(try LibraryCatalogBenchmarkSupport.measure(
                scenario: "primary-file-load",
                frameCount: frameCount,
                measurementIterations: iterations
            ) {
                let loaded = try XCTUnwrap(LibraryCatalogFile.loadPrimary(from: primary))
                return Self.outcome(loaded, payloadBytes: encoded.count)
            })

            XCTAssertTrue(cases.suffix(4).allSatisfy {
                $0.payloadBytes == expected.payloadBytes
                    && $0.frameCount == expected.frameCount
            })
        }

        let report = LibraryCatalogBenchmarkSupport.Report(
            schemaVersion: 1,
            catalogVersion: LibraryCatalog.currentVersion,
            storageKind: "whole-catalog-json-snapshot",
            configuration: Self.buildConfiguration,
            timingGateApplied: false,
            environment: LibraryCatalogBenchmarkSupport.environmentReport(),
            cases: cases
        )
        try LibraryCatalogBenchmarkSupport.write(
            report,
            to: ProcessInfo.processInfo.environment["NEGAFLOW_CATALOG_PERF_REPORT"]
        )

        XCTAssertEqual(cases.count, Self.frameCounts.count * 4)
        XCTAssertTrue(cases.allSatisfy { !$0.durationMilliseconds.samples.isEmpty })
        XCTAssertTrue(cases.allSatisfy { $0.payloadBytes > 0 })
    }

    private static var frameCounts: [Int] {
        guard let raw = ProcessInfo.processInfo.environment["NEGAFLOW_CATALOG_PERF_COUNTS"] else {
            return [1_000, 10_000, 50_000]
        }
        let values = raw.split(separator: ",").compactMap { Int($0) }
            .filter { (1...100_000).contains($0) }
        return values.isEmpty ? [1_000, 10_000, 50_000] : Array(Set(values)).sorted()
    }

    static func makeCatalog(frameCount: Int) -> LibraryCatalog {
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        let frame = ScanFrame(
            scanIndex: 0,
            rawScanURL: URL(fileURLWithPath: "/benchmark/source-000000.tif"),
            filmType: .colorNegative,
            sourceKind: .importedFile,
            sourcePixelWidth: 6_000,
            sourcePixelHeight: 4_000,
            sourceBitDepth: 16,
            scannedAt: epoch,
            id: deterministicUUID(0)
        )
        let template = LibraryFrameRecord(frame: frame)
        let records = (0..<frameCount).map { index -> LibraryFrameRecord in
            var record = template
            record.id = deterministicUUID(index)
            record.scanIndex = index + 1
            record.rawScanPath = String(format: "/benchmark/roll-%04d/frame-%06d.tif", index / 36, index)
            record.scannedAt = epoch.addingTimeInterval(TimeInterval(index))
            record.rating = index % 6
            record.pickState = index.isMultiple(of: 7) ? .picked : .unflagged
            record.customDisplayName = index.isMultiple(of: 11) ? "Frame \(index)" : nil
            return record
        }
        return LibraryCatalog(
            folders: ["/benchmark"],
            frames: records
        )
    }

    static func outcome(
        _ catalog: LibraryCatalog,
        payloadBytes: Int
    ) -> LibraryCatalogBenchmarkSupport.Outcome {
        LibraryCatalogBenchmarkSupport.Outcome(
            frameCount: catalog.frames.count,
            rollFrameCount: catalog.rolls.reduce(0) { $0 + $1.frameIDs.count },
            firstFrameID: catalog.frames.first?.id,
            lastFrameID: catalog.frames.last?.id,
            payloadBytes: payloadBytes
        )
    }

    private static func deterministicUUID(_ index: Int) -> UUID {
        let suffix = String(format: "%012llx", UInt64(index + 1))
        return UUID(uuidString: "00000000-0000-4000-8000-\(suffix)")!
    }

    static func fileSize(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }

    static var buildConfiguration: String {
        #if DEBUG
        "debug"
        #else
        "release"
        #endif
    }
}
