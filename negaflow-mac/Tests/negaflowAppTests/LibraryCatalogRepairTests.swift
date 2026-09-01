import XCTest
import Chromabase
import ScannerKit
@testable import negaflowApp

/// 되돌릴 수 있는 어긋남 때문에 라이브러리 전체가 잠기지 않아야 한다. 그러면서도 사진은
/// 하나도 잃지 않고, 정말로 판단할 수 없는 것은 여전히 막아야 한다.
@MainActor
final class LibraryCatalogRepairTests: XCTestCase {

    // MARK: 수리 규칙

    func testOrphanScanReservationIsDroppedWithoutLosingPhotos() {
        let records = (1...3).map { makeRecord(index: $0) }
        let catalog = LibraryCatalog(
            frames: records,
            rolls: [LibraryRoll.unassigned(
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                frameIDs: records.map(\.id)
            )],
            scanRollAssignments: [LibraryScanRollAssignment(
                sessionID: UUID(),
                rollID: UUID(),
                draftName: "Gone Roll",
                filmType: .colorNegative,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            )]
        )
        XCTAssertFalse(inspect(catalog).canOpenSafely)

        let result = LibraryCatalogRepair.repair(catalog)

        XCTAssertTrue(inspect(result.catalog).canOpenSafely)
        XCTAssertTrue(result.catalog.scanRollAssignments.isEmpty)
        XCTAssertEqual(result.catalog.frames.map(\.id), records.map(\.id))
    }

    func testFrameWithoutRollMembershipIsAdoptedInsteadOfBlocking() {
        let kept = makeRecord(index: 1)
        let orphan = makeRecord(index: 2)
        let catalog = LibraryCatalog(
            frames: [kept, orphan],
            rolls: [LibraryRoll.unassigned(
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                frameIDs: [kept.id]
            )]
        )
        XCTAssertFalse(inspect(catalog).canOpenSafely)

        let result = LibraryCatalogRepair.repair(catalog)

        XCTAssertTrue(inspect(result.catalog).canOpenSafely)
        XCTAssertEqual(result.catalog.frames.count, 2)
        XCTAssertEqual(
            Set(result.catalog.rolls.flatMap(\.frameIDs)),
            Set([kept.id, orphan.id])
        )
    }

    func testStaleDevelopRecipeFingerprintIsRecomputedNotBlocked() {
        var record = makeRecord(index: 1)
        record.userEditTracking = LibraryUserEditTracking(
            coverage: .tracked,
            ingestRecipeSHA256: String(repeating: "a", count: 64),
            currentRecipeSHA256: String(repeating: "b", count: 64),
            revision: 4
        )
        let catalog = makeSingleRollCatalog(records: [record])
        XCTAssertTrue(inspect(catalog).issues.contains { $0.code == .invalidUserEditTracking })

        let result = LibraryCatalogRepair.repair(catalog)

        XCTAssertTrue(inspect(result.catalog).canOpenSafely)
        let expected = try? LibraryDevelopRecipeFingerprint.sha256(
            filmType: record.filmType,
            presetID: record.presetID,
            params: record.params,
            imageTransform: record.imageTransform
        )
        XCTAssertNotNil(expected)
        XCTAssertEqual(result.catalog.frames[0].userEditTracking.currentRecipeSHA256, expected)
        // 편집 이력 자체는 지어내지 않고 그대로 둔다.
        XCTAssertEqual(result.catalog.frames[0].userEditTracking.revision, 4)
    }

    func testOutOfRangeRatingIsClampedAndCollectionsAreTidied() {
        var record = makeRecord(index: 1)
        record.rating = 9
        let missingFrameID = UUID()
        var catalog = makeSingleRollCatalog(records: [record])
        catalog.manualCollections = [LibraryManualCollection(
            id: UUID(),
            name: "   ",
            frameIDs: [record.id, record.id, missingFrameID]
        )]

        let result = LibraryCatalogRepair.repair(catalog)

        XCTAssertTrue(inspect(result.catalog).canOpenSafely)
        XCTAssertEqual(result.catalog.frames[0].rating, 5)
        XCTAssertEqual(result.catalog.manualCollections[0].frameIDs, [record.id])
        XCTAssertFalse(result.catalog.manualCollections[0].name.isEmpty)
    }

    func testRepairNeverDropsPhotoRecords() {
        var first = makeRecord(index: 1)
        first.rating = 42
        var second = makeRecord(index: 2)
        second.userEditTracking = LibraryUserEditTracking(
            coverage: .tracked,
            ingestRecipeSHA256: nil,
            currentRecipeSHA256: nil,
            revision: 7
        )
        let third = makeRecord(index: 3)
        let catalog = LibraryCatalog(
            frames: [first, second, third],
            rolls: [],
            scanRollAssignments: [LibraryScanRollAssignment(
                sessionID: UUID(),
                rollID: UUID(),
                draftName: "",
                filmType: .bwNegative,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            )]
        )

        let result = LibraryCatalogRepair.repair(catalog)

        XCTAssertTrue(inspect(result.catalog).canOpenSafely)
        XCTAssertEqual(
            Set(result.catalog.frames.map(\.id)),
            Set([first.id, second.id, third.id])
        )
    }

    func testUndecidableDamageStillBlocksInsteadOfBeingInvented() {
        var record = makeRecord(index: 1)
        record.rawScanPath = "   "
        let catalog = makeSingleRollCatalog(records: [record])

        let health = inspect(catalog)

        XCTAssertTrue(health.blocksOpen)
        XCTAssertNil(LibraryCatalogRepair.repairedCatalogIfOpenable(catalog))
    }

    // MARK: 여는 경로

    func testRepairableCatalogOpensAndIsRewrittenWithOriginalPreserved() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let catalogURL = root.appendingPathComponent("library.json")
        let defects = root.appendingPathComponent("defects", isDirectory: true)
        let backups = root.appendingPathComponent("Backups", isDirectory: true)

        let records = [makeRecord(index: 1), makeRecord(index: 2)]
        var catalog = makeSingleRollCatalog(records: records)
        catalog.scanRollAssignments = [LibraryScanRollAssignment(
            sessionID: UUID(),
            rollID: UUID(),
            draftName: "Gone Roll",
            filmType: .colorNegative,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )]
        try XCTUnwrap(LibraryCatalogFile.encode(catalog)).write(to: catalogURL, options: .atomic)

        guard case let .loaded(opened, recovered, _, repairs) = LibraryCatalogFile.prepareForUse(
            at: catalogURL,
            defectDirectory: defects,
            backupDirectory: backups
        ) else {
            return XCTFail("repairable catalog should open")
        }

        XCTAssertFalse(recovered)
        XCTAssertEqual(repairs?.isEmpty, false)
        XCTAssertEqual(opened.frames.count, 2)
        XCTAssertTrue(opened.scanRollAssignments.isEmpty)

        // 고친 결과가 자리에 남아, 다시 열 때는 수리가 필요 없어야 한다.
        guard case let .loaded(reopened, _, _, secondRepairs) = LibraryCatalogFile.prepareForUse(
            at: catalogURL,
            defectDirectory: defects,
            backupDirectory: backups
        ) else {
            return XCTFail("repaired catalog should reopen cleanly")
        }
        XCTAssertNil(secondRepairs)
        XCTAssertEqual(reopened.frames.count, 2)

        // 고치기 전 상태는 사본과 백업 세대 두 벌로 남는다.
        let sidelined = try FileManager.default.contentsOfDirectory(
            atPath: root.path
        ).filter { $0.hasPrefix("library.pre-repair-") }
        XCTAssertEqual(sidelined.count, 1)
        XCTAssertEqual(try LibraryBackupStore.generations(in: backups).count, 1)
    }

    func testLeftoverMigrationMarkerDoesNotPermanentlyBlockAFreshStart() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sqliteURL = root.appendingPathComponent("library.sqlite")

        // 마이그레이션은 예전에 끝났고 마커만 남았는데, 그 뒤 sqlite 가 사라진 상태.
        let marker = """
        {
          "createdAt" : "2026-07-12T07:30:20Z",
          "preservedLegacyFileName" : "library.pre-sqlite-deadbeef0000.json",
          "sourceCatalogVersion" : 1,
          "sourceSHA256" : "\(String(repeating: "d", count: 64))",
          "sqliteStorageVersion" : 1,
          "temporaryDatabaseFileName" : ".library-migrating-gone.sqlite",
          "version" : 1
        }
        """
        try Data(marker.utf8).write(
            to: root.appendingPathComponent("library.sqlite-migration.json"),
            options: .atomic
        )

        let result = LibraryCatalogFile.prepareForUse(
            at: sqliteURL,
            defectDirectory: root.appendingPathComponent("defects", isDirectory: true),
            backupDirectory: root.appendingPathComponent("Backups", isDirectory: true)
        )

        guard case .newLibrary = result else {
            return XCTFail("a stale migration marker must not block the library forever")
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("library.sqlite-migration.json").path
        ))
    }

    func testPreservedPreSQLiteJSONIsUsedWhenNothingElseRemains() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sqliteURL = root.appendingPathComponent("library.sqlite")
        let defects = root.appendingPathComponent("defects", isDirectory: true)
        let backups = root.appendingPathComponent("Backups", isDirectory: true)

        let records = [makeRecord(index: 1), makeRecord(index: 2)]
        let catalog = makeSingleRollCatalog(records: records)
        try XCTUnwrap(LibraryCatalogFile.encode(catalog)).write(
            to: root.appendingPathComponent("library.pre-sqlite-deadbeef0000.json"),
            options: .atomic
        )

        guard case let .loaded(recoveredCatalog, recovered, _, _) =
            LibraryCatalogFile.prepareForUse(
                at: sqliteURL,
                defectDirectory: defects,
                backupDirectory: backups
            ) else {
            return XCTFail("the preserved pre-sqlite original should be recovered")
        }
        XCTAssertTrue(recovered)
        XCTAssertEqual(recoveredCatalog.frames.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sqliteURL.path))
    }

    // MARK: 픽스처

    private func inspect(_ catalog: LibraryCatalog) -> LibraryCatalogHealthReport {
        LibraryCatalogHealthInspector.inspect(catalog, includeWarnings: false)
    }

    private func makeRecord(index: Int) -> LibraryFrameRecord {
        LibraryFrameRecord(frame: ScanFrame(
            scanIndex: index,
            rawScanURL: URL(fileURLWithPath: "/library/frame-\(index).tiff"),
            filmType: .colorNegative
        ))
    }

    private func makeSingleRollCatalog(records: [LibraryFrameRecord]) -> LibraryCatalog {
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
            "negaflow-catalog-repair-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
