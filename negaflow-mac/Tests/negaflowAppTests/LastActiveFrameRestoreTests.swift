import XCTest
@testable import Chromabase
@testable import ScannerKit
@testable import negaflowApp

/// 앱을 다시 켜면 **마지막으로 작업하던 사진**이 다시 떠야 한다.
///
/// 예전에는 카탈로그에 그 값을 저장하지 않아서, 시작할 때마다
/// `selectMostRecentAvailableFrameIfNeeded()` 가 `scannedAt` 이 가장 늦은 사진을 골랐다.
@MainActor
final class LastActiveFrameRestoreTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-last-active-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
        try await super.tearDown()
    }

    func testCatalogCarriesTheLastActiveFrameAcrossEncoding() throws {
        let id = UUID()
        let catalog = LibraryCatalog(lastActiveFrameID: id)
        let data = try JSONEncoder().encode(catalog)
        let decoded = try JSONDecoder().decode(LibraryCatalog.self, from: data)
        XCTAssertEqual(decoded.lastActiveFrameID, id)
    }

    /// 예전 카탈로그(그 키가 없는 JSON)도 그대로 열려야 한다.
    func testCatalogWithoutTheKeyStillDecodes() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try JSONEncoder().encode(LibraryCatalog())
            ) as? [String: Any]
        )
        object.removeValue(forKey: "lastActiveFrameID")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(LibraryCatalog.self, from: data)
        XCTAssertNil(decoded.lastActiveFrameID)
    }

    /// 시작 선택은 가장 최근 사진이 아니라 기억해 둔 사진을 고른다.
    func testLaunchSelectionPrefersTheRememberedFrame() throws {
        let model = try makeModel()
        let older = try makeFrame(index: 1, scannedAt: Date(timeIntervalSince1970: 1_000))
        let newest = try makeFrame(index: 2, scannedAt: Date(timeIntervalSince1970: 9_000))
        model.frames = [older, newest]
        model.updateInteractionScope([older.id, newest.id])

        model.restoredLastActiveFrameID = older.id
        XCTAssertTrue(model.selectMostRecentAvailableFrameIfNeeded())
        XCTAssertEqual(model.selectedFrameID, older.id, "기억해 둔 사진 대신 최신 사진을 골랐다")
        XCTAssertNil(model.restoredLastActiveFrameID, "한 번 쓰고 비워야 한다")
    }

    /// 기억해 둔 사진이 사라졌으면 기존 규칙(가장 최근)으로 돌아간다.
    func testLaunchSelectionFallsBackWhenTheRememberedFrameIsGone() throws {
        let model = try makeModel()
        let older = try makeFrame(index: 1, scannedAt: Date(timeIntervalSince1970: 1_000))
        let newest = try makeFrame(index: 2, scannedAt: Date(timeIntervalSince1970: 9_000))
        model.frames = [older, newest]
        model.updateInteractionScope([older.id, newest.id])

        model.restoredLastActiveFrameID = UUID()   // 카탈로그에서 사라진 사진
        XCTAssertTrue(model.selectMostRecentAvailableFrameIfNeeded())
        XCTAssertEqual(model.selectedFrameID, newest.id)
    }

    /// 원본 존재 확인이 아직 백그라운드에서 도는 동안에는 기억을 소비하지 않는다.
    ///
    /// 라이브러리가 256장을 넘으면 그 확인이 비동기로 바뀌고, 끝나기 전에는 모든 사진이
    /// `.unknown`(= 사용 불가)으로 보인다. 예전에는 그 순간 기억을 버려서, 판정이 끝난 뒤에도
    /// 돌아갈 사진이 남지 않았다 — 앱을 켜면 아무 사진도 뜨지 않았고, 종료할 때 그 빈 선택이
    /// 카탈로그에 기록돼 기억 자체가 사라졌다(실기 재현: 268장 라이브러리).
    func testRememberedFrameSurvivesWhileSourceAvailabilityIsStillResolving() throws {
        let model = try makeModel()
        let older = try makeFrame(index: 1, scannedAt: Date(timeIntervalSince1970: 1_000))
        let newest = try makeFrame(index: 2, scannedAt: Date(timeIntervalSince1970: 9_000))
        model.frames = [older, newest]
        model.updateInteractionScope([older.id, newest.id])
        model.restoredLastActiveFrameID = older.id

        // 아직 판정 전: 전부 unknown.
        model.librarySourceAvailabilityCache = [older.id: .unknown, newest.id: .unknown]
        XCTAssertFalse(model.hasResolvedSourceAvailability)
        XCTAssertFalse(model.selectMostRecentAvailableFrameIfNeeded())
        XCTAssertNil(model.selectedFrameID, "판정 전에는 아무 사진도 고르지 않는다")
        XCTAssertEqual(
            model.restoredLastActiveFrameID, older.id,
            "판정 전에 기억을 버리면 복원할 기회가 영영 사라진다"
        )

        // 판정 완료 → 기억해 둔 사진으로 돌아간다.
        model.librarySourceAvailabilityCache = [older.id: .online, newest.id: .online]
        model.advanceSourceAvailabilityRevision()
        XCTAssertTrue(model.hasResolvedSourceAvailability)
        XCTAssertTrue(model.selectMostRecentAvailableFrameIfNeeded())
        XCTAssertEqual(model.selectedFrameID, older.id)
        XCTAssertNil(model.restoredLastActiveFrameID, "성공했으면 한 번 쓰고 비운다")
    }

    /// 판정이 끝났는데 기억해 둔 사진을 쓸 수 없으면 그때는 기억을 버리고 폴백한다.
    func testRememberedFrameIsDiscardedOnlyAfterAvailabilityIsKnown() throws {
        let model = try makeModel()
        let older = try makeFrame(index: 1, scannedAt: Date(timeIntervalSince1970: 1_000))
        let newest = try makeFrame(index: 2, scannedAt: Date(timeIntervalSince1970: 9_000))
        model.frames = [older, newest]
        model.updateInteractionScope([older.id, newest.id])
        model.restoredLastActiveFrameID = older.id

        model.librarySourceAvailabilityCache = [older.id: .offline, newest.id: .online]
        model.advanceSourceAvailabilityRevision()
        XCTAssertTrue(model.selectMostRecentAvailableFrameIfNeeded())
        XCTAssertEqual(model.selectedFrameID, newest.id, "쓸 수 없는 사진 대신 최신으로 폴백한다")
        XCTAssertNil(model.restoredLastActiveFrameID)
    }

    // MARK: 하네스

    private func makeModel() throws -> AppModel {
        AppModel(
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("backups")
        )
    }

    private func makeFrame(index: Int, scannedAt: Date) throws -> ScanFrame {
        let source = root.appendingPathComponent("frame-\(index).tif")
        try MockScannerBackend.writeSyntheticNegative(width: 32, height: 24, to: source)
        return ScanFrame(
            scanIndex: index,
            rawScanURL: source,
            filmType: .colorNegative,
            sourceKind: .scannerTIFF,
            scannedAt: scannedAt
        )
    }
}
