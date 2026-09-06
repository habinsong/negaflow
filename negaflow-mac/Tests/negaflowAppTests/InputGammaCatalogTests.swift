import XCTest
import SQLite3
import Chromabase
@testable import negaflowApp

@MainActor
final class InputGammaCatalogTests: XCTestCase {
    func testV6JSONMigrationPreservesRecipeAndDefaults() throws {
        let frame = ScanFrame(scanIndex: 1, rawScanURL: URL(fileURLWithPath: "/offline/scan.tiff"), filmType: .colorNegative)
        frame.params.exposure = 0.35
        var legacy = LibraryCatalog(frames: [LibraryFrameRecord(frame: frame)])
        legacy.version = 6
        legacy.minimumReaderVersion = 6
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(legacy)
        guard case .loaded(let migrated, let sourceVersion) = LibraryCatalogFile.decodeResult(data) else {
            return XCTFail("v6 카탈로그를 보존하여 승격해야 합니다.")
        }
        XCTAssertEqual(sourceVersion, 6)
        XCTAssertEqual(migrated.version, 7)
        XCTAssertEqual(migrated.minimumReaderVersion, 7)
        XCTAssertEqual(migrated.frames[0].id, frame.id)
        XCTAssertEqual(migrated.frames[0].params, frame.params)
        XCTAssertEqual(migrated.frames[0].params.inputGamma, .automatic)
    }

    func testSQLiteV6MigratesAndRoundTripsExplicitInput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("catalog.sqlite")
        let frame = ScanFrame(scanIndex: 1, rawScanURL: root.appendingPathComponent("scan.tiff"), filmType: .colorNegative)
        let catalog = LibraryCatalog(frames: [LibraryFrameRecord(frame: frame)])
        XCTAssertTrue(LibraryCatalogSQLiteStore.write(catalog, to: url))
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "UPDATE catalog_metadata SET catalog_version=6, minimum_reader_version=6", nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)
        XCTAssertTrue(LibraryCatalogSQLiteStore.isValidRecoverySource(at: url))
        guard case .loaded(var migrated, let version) = LibraryCatalogFile.read(from: url) else {
            return XCTFail("SQLite v6를 읽을 수 있어야 합니다.")
        }
        XCTAssertEqual(version, 6)
        XCTAssertEqual(migrated.version, 7)
        XCTAssertEqual(migrated.frames[0].id, frame.id)
        migrated.frames[0].params.inputGamma = try .power(1.2345)
        migrated.frames[0].params.baseScale = try FilmBaseScale(0.75)
        XCTAssertTrue(LibraryCatalogSQLiteStore.write(migrated, to: url))
        guard case .loaded(let stored, let storedVersion) = LibraryCatalogFile.read(from: url) else {
            return XCTFail("승격한 설정을 다시 읽을 수 있어야 합니다.")
        }
        XCTAssertEqual(storedVersion, 7)
        XCTAssertEqual(stored, migrated)
    }

    func testThumbnailIdentityIncludesInputAndActiveScale() throws {
        let frame = ScanFrame(scanIndex: 1, rawScanURL: URL(fileURLWithPath: "/offline/scan.tiff"), filmType: .colorNegative)
        let model = AppModel()
        let originalRaw = model.rawThumbnailFileURL(for: frame)
        let originalDeveloped = model.thumbnailFileURL(for: frame)
        frame.params.baseScale = try FilmBaseScale(0.5)
        XCTAssertEqual(model.rawThumbnailFileURL(for: frame), originalRaw)
        XCTAssertNotEqual(model.thumbnailFileURL(for: frame), originalDeveloped)
        frame.params.inputGamma = try .power(1.8)
        let gammaRaw = model.rawThumbnailFileURL(for: frame)
        XCTAssertNotEqual(gammaRaw, originalRaw)
        frame.params.inputGamma = try .power(1.8001)
        XCTAssertNotEqual(model.rawThumbnailFileURL(for: frame), gammaRaw)
    }
}
