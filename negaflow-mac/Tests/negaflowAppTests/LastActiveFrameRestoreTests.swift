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
