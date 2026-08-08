import Foundation
import XCTest
@testable import negaflowApp

@MainActor
final class LibraryCatalogSQLitePerformanceTests: XCTestCase {
    func testSQLiteCatalogPerformanceWhenEnabled() throws {
        guard ProcessInfo.processInfo.environment["NEGAFLOW_SQLITE_CATALOG_PERF"] == "1" else {
            throw XCTSkip("Set NEGAFLOW_SQLITE_CATALOG_PERF=1 to run the SQLite catalog benchmark.")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-sqlite-catalog-benchmark-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var cases: [LibraryCatalogBenchmarkSupport.CaseReport] = []
        for frameCount in [1_000, 10_000, 50_000] {
            let catalog = LibraryCatalogPerformanceTests.makeCatalog(frameCount: frameCount)
            let url = root.appendingPathComponent("catalog-\(frameCount).sqlite")
            let iterations = frameCount >= 50_000 ? 3 : 5
            cases.append(try LibraryCatalogBenchmarkSupport.measure(
                scenario: "sqlite-upsert-commit",
                frameCount: frameCount,
                measurementIterations: iterations,
                prepare: {
                    try? FileManager.default.removeItem(at: url)
                    try? FileManager.default.removeItem(at: LibraryCatalogFile.backupURL(for: url))
                }
            ) {
                guard LibraryCatalogFile.writeCatalogSync(catalog, to: url) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                return LibraryCatalogPerformanceTests.outcome(
                    catalog,
                    payloadBytes: try LibraryCatalogPerformanceTests.fileSize(url)
                )
            })

            guard LibraryCatalogFile.writeCatalogSync(catalog, to: url) else {
                throw CocoaError(.fileWriteUnknown)
            }
            cases.append(try LibraryCatalogBenchmarkSupport.measure(
                scenario: "sqlite-primary-load",
                frameCount: frameCount,
                measurementIterations: iterations
            ) {
                let loaded = try XCTUnwrap(LibraryCatalogFile.loadPrimary(from: url))
                return LibraryCatalogPerformanceTests.outcome(
                    loaded,
                    payloadBytes: try LibraryCatalogPerformanceTests.fileSize(url)
                )
            })
            cases.append(try LibraryCatalogBenchmarkSupport.measure(
                scenario: "sqlite-no-change-commit",
                frameCount: frameCount,
                measurementIterations: iterations
            ) {
                guard LibraryCatalogFile.writeCatalogSync(catalog, to: url) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                return LibraryCatalogPerformanceTests.outcome(
                    catalog,
                    payloadBytes: try LibraryCatalogPerformanceTests.fileSize(url)
                )
            })

            var oneFrameChanged = catalog
            oneFrameChanged.frames[frameCount / 2].rating = 4
            cases.append(try LibraryCatalogBenchmarkSupport.measure(
                scenario: "sqlite-one-frame-commit",
                frameCount: frameCount,
                measurementIterations: iterations,
                prepare: {
                    guard LibraryCatalogFile.writeCatalogSync(catalog, to: url) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                }
            ) {
                guard LibraryCatalogFile.writeCatalogSync(oneFrameChanged, to: url) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                return LibraryCatalogPerformanceTests.outcome(
                    oneFrameChanged,
                    payloadBytes: try LibraryCatalogPerformanceTests.fileSize(url)
                )
            })
            cases.append(try LibraryCatalogBenchmarkSupport.measure(
                scenario: "sqlite-acknowledged-one-frame-commit",
                frameCount: frameCount,
                measurementIterations: iterations,
                prepare: {
                    guard case .success = LibraryCatalogFile.commitAndVerify(
                        catalog,
                        to: url,
                        defectDirectory: root.appendingPathComponent(
                            "defects",
                            isDirectory: true
                        )
                    ) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                }
            ) {
                guard case .success = LibraryCatalogFile.commitAndVerify(
                    oneFrameChanged,
                    to: url,
                    defectDirectory: root.appendingPathComponent("defects", isDirectory: true)
                ) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                return LibraryCatalogPerformanceTests.outcome(
                    oneFrameChanged,
                    payloadBytes: try LibraryCatalogPerformanceTests.fileSize(url)
                )
            })
            cases.append(try LibraryCatalogBenchmarkSupport.measure(
                scenario: "sqlite-incremental-safety-check",
                frameCount: frameCount,
                measurementIterations: iterations
            ) {
                let health = LibraryCatalogHealthInspector.inspect(
                    oneFrameChanged,
                    defectDirectory: root.appendingPathComponent("defects", isDirectory: true),
                    includeWarnings: false,
                    validatedPreviousCatalog: catalog
                )
                guard health.canOpenSafely else { throw CocoaError(.fileReadCorruptFile) }
                return LibraryCatalogPerformanceTests.outcome(
                    oneFrameChanged,
                    payloadBytes: try LibraryCatalogPerformanceTests.fileSize(url)
                )
            })
        }

        try LibraryCatalogBenchmarkSupport.write(
            LibraryCatalogBenchmarkSupport.Report(
                schemaVersion: 1,
                catalogVersion: LibraryCatalog.currentVersion,
                storageKind: "sqlite-row-store-v1",
                configuration: LibraryCatalogPerformanceTests.buildConfiguration,
                timingGateApplied: false,
                environment: LibraryCatalogBenchmarkSupport.environmentReport(),
                cases: cases
            ),
            to: ProcessInfo.processInfo.environment["NEGAFLOW_SQLITE_CATALOG_PERF_REPORT"]
        )
        XCTAssertEqual(cases.count, 18)
    }
}
