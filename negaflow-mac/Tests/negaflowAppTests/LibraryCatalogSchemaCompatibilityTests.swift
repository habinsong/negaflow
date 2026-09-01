import XCTest
import Chromabase
@testable import negaflowApp

/// 앱이 올라가면서 저장 스키마가 자라도 예전 카탈로그는 그대로 열려야 한다.
/// 실제로 이것 때문에 멀쩡한 라이브러리가 "안전하게 열 수 없음" 으로 막힌 적이 있다:
/// 쓰기 경로에는 새 컬럼을 붙이는 마이그레이션이 있었지만, 읽기는 READONLY 라
/// 없는 컬럼을 SELECT 하다 실패했고 그 마이그레이션에 영영 닿지 못했다.
@MainActor
final class LibraryCatalogSchemaCompatibilityTests: XCTestCase {

    func testCatalogWrittenBeforeAColumnWasAddedStillOpens() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let catalogURL = root.appendingPathComponent("library.sqlite")
        let records = [makeRecord(index: 1), makeRecord(index: 2)]
        XCTAssertTrue(LibraryCatalogSQLiteStore.write(makeCatalog(records), to: catalogURL))

        // 그 컬럼이 아직 없던 시절의 파일을 만든다.
        try runSQL(
            "ALTER TABLE catalog_metadata DROP COLUMN last_active_frame_id",
            on: catalogURL
        )

        guard case let .loaded(catalog, _) = LibraryCatalogFile.read(from: catalogURL) else {
            return XCTFail("a catalog from an older schema must still be readable")
        }
        XCTAssertEqual(catalog.frames.count, 2)
        XCTAssertNil(catalog.lastActiveFrameID)

        guard case let .loaded(opened, _, _, _) = LibraryCatalogFile.prepareForUse(
            at: catalogURL,
            defectDirectory: root.appendingPathComponent("defects", isDirectory: true),
            backupDirectory: root.appendingPathComponent("Backups", isDirectory: true)
        ) else {
            return XCTFail("a catalog from an older schema must open")
        }
        XCTAssertEqual(opened.frames.count, 2)
    }

    func testUnreadableSideRecordIsSkippedInsteadOfLosingTheWholeLibrary() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let catalogURL = root.appendingPathComponent("library.sqlite")
        let records = [makeRecord(index: 1), makeRecord(index: 2)]
        var catalog = makeCatalog(records)
        catalog.manualCollections = [LibraryManualCollection(
            id: UUID(),
            name: "Keepers",
            frameIDs: [records[0].id]
        )]
        XCTAssertTrue(LibraryCatalogSQLiteStore.write(catalog, to: catalogURL))

        // 앞으로 형식이 바뀌어 이 앱이 못 읽는 줄이 하나 섞인 상황.
        try runSQL(
            """
            INSERT INTO manual_collections(id, position, payload)
            VALUES ('\(UUID().uuidString)', 999, CAST('{"unreadable":true}' AS BLOB))
            """,
            on: catalogURL
        )

        guard case let .loaded(reread, _) = LibraryCatalogFile.read(from: catalogURL) else {
            return XCTFail("one unreadable side record must not sink the catalog")
        }
        XCTAssertEqual(reread.frames.count, 2)
        XCTAssertEqual(reread.manualCollections.map(\.name), ["Keepers"])
    }

    func testUnreadablePhotoRecordStillFailsClosed() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let catalogURL = root.appendingPathComponent("library.sqlite")
        let records = [makeRecord(index: 1)]
        XCTAssertTrue(LibraryCatalogSQLiteStore.write(makeCatalog(records), to: catalogURL))

        // 사진 레코드는 라이브러리의 뼈대다. 못 읽으면 조용히 넘어가서는 안 된다.
        try runSQL(
            """
            INSERT INTO frames(id, position, payload)
            VALUES ('\(UUID().uuidString)', 999, CAST('{"unreadable":true}' AS BLOB))
            """,
            on: catalogURL
        )

        guard case .invalid = LibraryCatalogSQLiteStore.read(from: catalogURL) else {
            return XCTFail("an unreadable photo record must fail closed")
        }
    }

    func testJSONCatalogSkipsAnUnreadableSideRecordButKeepsRequiredKeys() throws {
        let records = [makeRecord(index: 1), makeRecord(index: 2)]
        var catalog = makeCatalog(records)
        catalog.manualCollections = [LibraryManualCollection(
            id: UUID(),
            name: "Keepers",
            frameIDs: [records[0].id]
        )]
        let encoded = try XCTUnwrap(LibraryCatalogFile.encode(catalog))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        // 백업 세대는 JSON 이다. 예전/새 앱이 쓴 부수 기록이 섞여도 복원할 수 있어야 한다.
        var collections = try XCTUnwrap(object["manualCollections"] as? [[String: Any]])
        collections.append(["unreadable": true])
        object["manualCollections"] = collections
        let patched = try JSONSerialization.data(withJSONObject: object)

        guard case let .loaded(decoded, _) = LibraryCatalogFile.decodeResult(patched) else {
            return XCTFail("one unreadable side record must not sink the backup")
        }
        XCTAssertEqual(decoded.frames.count, 2)
        XCTAssertEqual(decoded.manualCollections.map(\.name), ["Keepers"])

        // 반면 키가 통째로 없는 것은 잘린 카탈로그다 — 빈 목록으로 오해하면 안 된다.
        object.removeValue(forKey: "manualCollections")
        let truncated = try JSONSerialization.data(withJSONObject: object)
        guard case .invalid = LibraryCatalogFile.decodeResult(truncated) else {
            return XCTFail("a truncated catalog must still fail closed")
        }
    }

    func testUnknownFieldValueLosesThatValueNotThePhoto() throws {
        let records = [makeRecord(index: 1), makeRecord(index: 2)]
        let encoded = try XCTUnwrap(LibraryCatalogFile.encode(makeCatalog(records)))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var frames = try XCTUnwrap(object["frames"] as? [[String: Any]])

        // 뒤에 나온 빌드가 쓴 값, 형식이 어긋난 값, 낡은 이력 한 줄이 섞인 사진.
        frames[0]["pickState"] = "somethingThisBuildDoesNotKnow"
        frames[0]["customDisplayName"] = 42
        frames[0]["scannedAt"] = "not-a-date"
        frames[0]["developHistory"] = [["unreadable": true]]
        object["frames"] = frames
        let patched = try JSONSerialization.data(withJSONObject: object)

        guard case let .loaded(decoded, _) = LibraryCatalogFile.decodeResult(patched) else {
            return XCTFail("one unknown field value must not cost the whole library")
        }
        // 사진은 두 장 다 남는다. 건너뛰면 다음 저장에서 카탈로그에서 사라지기 때문이다.
        XCTAssertEqual(decoded.frames.count, 2)
        XCTAssertEqual(decoded.frames.map(\.id), records.map(\.id))

        let repaired = decoded.frames[0]
        XCTAssertEqual(repaired.pickState, .unflagged)
        XCTAssertNil(repaired.customDisplayName)
        XCTAssertEqual(repaired.scannedAt, .distantPast)
        XCTAssertTrue(repaired.developHistory.isEmpty)
        // 사진의 정체를 이루는 값은 되돌리지 않고 그대로 읽는다.
        XCTAssertEqual(repaired.rawScanPath, records[0].rawScanPath)
        XCTAssertEqual(repaired.filmType, records[0].filmType)
    }

    func testUnknownFilmTypeStillFailsClosed() throws {
        let records = [makeRecord(index: 1)]
        let encoded = try XCTUnwrap(LibraryCatalogFile.encode(makeCatalog(records)))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var frames = try XCTUnwrap(object["frames"] as? [[String: Any]])

        // 필름 종류는 사진이 어떻게 현상되는지를 정한다. 임의로 되돌리면 사진을 살리는 것이
        // 아니라 다른 사진으로 바꾸는 것이라, 여기서는 여전히 닫아야 한다.
        frames[0]["filmType"] = "unknownProcess"
        object["frames"] = frames
        let patched = try JSONSerialization.data(withJSONObject: object)

        guard case .invalid = LibraryCatalogFile.decodeResult(patched) else {
            return XCTFail("a value that decides how the photo develops must fail closed")
        }
    }

    // MARK: 픽스처

    private func makeRecord(index: Int) -> LibraryFrameRecord {
        LibraryFrameRecord(frame: ScanFrame(
            scanIndex: index,
            rawScanURL: URL(fileURLWithPath: "/library/frame-\(index).tiff"),
            filmType: .colorNegative
        ))
    }

    private func makeCatalog(_ records: [LibraryFrameRecord]) -> LibraryCatalog {
        LibraryCatalog(
            frames: records,
            rolls: [LibraryRoll.unassigned(
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                frameIDs: records.map(\.id)
            )]
        )
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-schema-compat-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func runSQL(_ sql: String, on url: URL) throws {
        let executable = URL(fileURLWithPath: "/usr/bin/sqlite3")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw XCTSkip("sqlite3 CLI is unavailable")
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = [url.path, sql]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let message = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        guard process.terminationStatus == 0 else {
            throw XCTSkip("sqlite3 could not prepare the fixture: \(message)")
        }
    }
}
