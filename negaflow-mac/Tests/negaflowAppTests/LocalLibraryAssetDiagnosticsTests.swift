import XCTest
@testable import negaflowApp

/// 지정한 카탈로그와 보정 파일을 읽기만 합니다. 복구·저장·원본 변경은 수행하지 않습니다.
@MainActor
final class LocalLibraryAssetDiagnosticsTests: XCTestCase {
    func testCatalogAndEveryReferencedDefectRecipe() throws {
        let env = ProcessInfo.processInfo.environment
        guard let catalogPath = env["NEGAFLOW_DIAGNOSTIC_CATALOG"],
              let defectPath = env["NEGAFLOW_DIAGNOSTIC_DEFECTS"] else {
            throw XCTSkip("NEGAFLOW_DIAGNOSTIC_CATALOG와 NEGAFLOW_DIAGNOSTIC_DEFECTS가 필요합니다.")
        }
        let catalog = try XCTUnwrap(LibraryCatalogFile.loadPrimary(from: URL(fileURLWithPath: catalogPath)))
        let defects = URL(fileURLWithPath: defectPath, isDirectory: true)
        let health = LibraryCatalogHealthInspector.inspect(catalog, defectDirectory: defects, includeWarnings: false)
        XCTAssertTrue(health.canOpenSafely, "\(health.issues.map(\.code))")
        let records = catalog.frames.filter { $0.hasDefectEdits == true }
        for record in records {
            let restoration = DefectRecipeRestoration.read(frameID: record.id, in: defects)
            let snapshot = try XCTUnwrap(restoration.snapshot, "\(record.id)")
            XCTAssertFalse(restoration.items.isEmpty)
            XCTAssertEqual(restoration.items.count, snapshot.items.count)
            let frame = record.makeFrame(presets: [])
            restoration.apply(to: frame)
            XCTAssertFalse(frame.defectEditsNeedRestore)
            XCTAssertEqual(frame.defectRecipeIdentity, snapshot.identity)
            XCTAssertTrue(DefectSidecarCommitCache.shared.matches(snapshot.identity,
                at: DefectSidecarFile.url(for: record.id, in: defects)))
            XCTAssertEqual(try AppModel.defectSourceIdentity(for: frame.rawScanURL), snapshot.identity.sourceIdentity)
        }
        print("검사 완료: 카탈로그 \(catalog.frames.count)장, 결함 보정 파일 \(records.count)개")
    }
}
