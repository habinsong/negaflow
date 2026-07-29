import Foundation
import XCTest
import Chromabase
import ScannerKit
@testable import negaflowApp

/// standard/strict 검증 수준의 실제 비용 차이를 재는 벤치. 기본 실행에서는 건너뛴다.
///
///     NEGAFLOW_EXPORT_VERIFICATION_PERF=1 swift test --filter ExportVerificationPerformanceTests
@MainActor
final class ExportVerificationPerformanceTests: XCTestCase {
    func testVerificationLevelExportCostWhenEnabled() throws {
        guard ProcessInfo.processInfo.environment["NEGAFLOW_EXPORT_VERIFICATION_PERF"] == "1" else {
            throw XCTSkip("Set NEGAFLOW_EXPORT_VERIFICATION_PERF=1 to run the export verification benchmark.")
        }
        let isolation = CleanedRawFolderIsolation()
        defer { isolation.restore() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-export-verification-benchmark-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // 실측 대상은 큰 원본이다 — 해시 패스 비용은 파일 크기에 비례한다.
        let rawURL = root.appendingPathComponent("benchmark-source.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 4000, height: 3000, to: rawURL)
        let sourceBytes = try FileManager.default.attributesOfItem(atPath: rawURL.path)[.size] as? Int ?? 0
        let frame = ScanFrame(scanIndex: 1, rawScanURL: rawURL, filmType: .colorPositive)
        let sourceIdentity = try RenderManifest.sourceIdentity(for: rawURL)
        let fileIdentity = ExportArtifactFileIdentityInspector.sourceFile(at: rawURL)

        func measure(
            level: ExportVerificationLevel,
            writeOriginalRaw: Bool,
            writeMainFlatMaster: Bool = false,
            iterations: Int = 5
        ) throws -> Double {
            var samples: [Double] = []
            for index in 0..<iterations {
                let outputURL = root.appendingPathComponent(
                    "out-\(level.rawValue)-\(writeOriginalRaw)-\(writeMainFlatMaster)-\(index).jpg"
                )
                let plan = ExportFrameSnapshotBuilder.build(
                    frame: frame,
                    sourceIdentity: sourceIdentity,
                    outputURL: outputURL,
                    format: .jpeg,
                    writeSidecar: false,
                    writeMainFlatMaster: writeMainFlatMaster,
                    writeOriginalRaw: writeOriginalRaw,
                    options: .standard,
                    scannerModel: nil,
                    backendUsed: nil,
                    sourceFileIdentity: fileIdentity,
                    verificationLevel: level
                )
                let start = Date()
                _ = try ExportFrameWriter.write(plan.snapshot)
                samples.append(Date().timeIntervalSince(start) * 1000)
            }
            samples.sort()
            return samples[samples.count / 2]
        }

        let plainStandard = try measure(level: .standard, writeOriginalRaw: false)
        let plainStrict = try measure(level: .strict, writeOriginalRaw: false)
        let pairedStandard = try measure(level: .standard, writeOriginalRaw: true)
        let pairedStrict = try measure(level: .strict, writeOriginalRaw: true)
        let mainFlatStandard = try measure(
            level: .standard,
            writeOriginalRaw: false,
            writeMainFlatMaster: true
        )
        let bothStandard = try measure(
            level: .standard,
            writeOriginalRaw: true,
            writeMainFlatMaster: true
        )

        print(String(
            format: """
            [export-verification-perf] source=%.1fMB
              jpeg only        standard %.0f ms | strict %.0f ms | saved %.0f ms (%.0f%%)
              jpeg + original  standard %.0f ms | strict %.0f ms | saved %.0f ms (%.0f%%)
              pair cost (standard): original +%.0f ms | main-flat +%.0f ms | both +%.0f ms
            """,
            Double(sourceBytes) / 1_048_576,
            plainStandard, plainStrict, plainStrict - plainStandard,
            (plainStrict - plainStandard) / plainStrict * 100,
            pairedStandard, pairedStrict, pairedStrict - pairedStandard,
            (pairedStrict - pairedStandard) / pairedStrict * 100,
            pairedStandard - plainStandard,
            mainFlatStandard - plainStandard,
            bothStandard - plainStandard
        ))

        XCTAssertLessThan(plainStandard, plainStrict)
        XCTAssertLessThan(pairedStandard, pairedStrict)
    }

    /// 앱이 실제로 도는 전체 경로(MainActor 트랜잭션 + writer + 저널 + 카탈로그 커밋)를 잰다.
    func testFullExportTransactionCostWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["NEGAFLOW_EXPORT_VERIFICATION_PERF"] == "1" else {
            throw XCTSkip("Set NEGAFLOW_EXPORT_VERIFICATION_PERF=1 to run the export verification benchmark.")
        }
        let isolation = CleanedRawFolderIsolation()
        defer { isolation.restore() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-export-transaction-benchmark-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let model = AppModel(
            libraryCatalogURL: root.appendingPathComponent("library.sqlite"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )
        await model.restoreLibraryOnLaunch()
        let rawURL = root.appendingPathComponent("transaction-source.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 4000, height: 3000, to: rawURL)
        let sourceBytes = try FileManager.default.attributesOfItem(atPath: rawURL.path)[.size] as? Int ?? 0
        let frame = ScanFrame(scanIndex: 1, rawScanURL: rawURL, filmType: .colorPositive)
        model.frames = [frame]
        XCTAssertTrue(model.assignNewPersistentFrames([frame]))

        func measure(level: ExportVerificationLevel, iterations: Int = 5) async throws -> Double {
            model.exportVerificationLevel = level
            var samples: [Double] = []
            for index in 0..<iterations {
                let outputURL = root.appendingPathComponent("tx-\(level.rawValue)-\(index).jpg")
                let start = Date()
                let result = await model.runExportFrameTransaction(
                    frame,
                    to: outputURL,
                    format: .jpeg,
                    writeSidecar: false,
                    writeMainFlatMaster: false,
                    writeOriginalRaw: false,
                    options: .standard,
                    recipeIdentity: nil,
                    reportsGlobalStatus: false
                )
                samples.append(Date().timeIntervalSince(start) * 1000)
                guard case .completed = result else {
                    XCTFail("export failed: \(result)")
                    return samples[0]
                }
            }
            samples.sort()
            return samples[samples.count / 2]
        }

        let standard = try await measure(level: .standard)
        let strict = try await measure(level: .strict)
        print(String(
            format: "[export-transaction-perf] source=%.1fMB standard %.0f ms | strict %.0f ms | saved %.0f ms (%.0f%%)",
            Double(sourceBytes) / 1_048_576,
            standard,
            strict,
            strict - standard,
            (strict - standard) / strict * 100
        ))
        XCTAssertLessThan(standard, strict)
    }
}
