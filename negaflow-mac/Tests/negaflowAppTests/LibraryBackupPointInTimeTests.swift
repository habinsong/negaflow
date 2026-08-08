import XCTest
@testable import negaflowApp

@MainActor
final class LibraryBackupPointInTimeTests: XCTestCase {
    func testCatalogAndAuthoritativeRecipeStayOnFrozenGenerationDuringMutation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-backup-point-in-time-\(UUID().uuidString)", isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let defects = root.appendingPathComponent("defects", isDirectory: true)
        let backups = root.appendingPathComponent("backups", isDirectory: true)
        let model = AppModel(
            backupScheduleStore: LibraryBackupScheduleStore(
                defaults: try XCTUnwrap(UserDefaults(suiteName: "point-in-time-\(UUID().uuidString)"))
            ),
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: defects,
            libraryBackupDirectoryURL: backups
        )
        let roll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Frozen",
            filmType: .colorNegative,
            activate: true
        ))
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/offline/frozen.tif"),
            filmType: .colorNegative
        )
        var before = makeEdit(label: .guided(count: 1))
        before.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        frame.customDisplayName = "Before freeze"
        frame.defectEdits = [before]
        model.frames = [frame]
        XCTAssertTrue(model.assignNewPersistentFrames([frame], toRollID: roll.id))
        model.libraryPersistenceEnabled = true

        let succeeded = await model.createLibraryBackupNow(
            at: Date(timeIntervalSince1970: 100),
            afterFreeze: {
                frame.customDisplayName = "After freeze"
                model.setDefectEditEnabled(frame, id: before.id, enabled: false)
            }
        )

        XCTAssertTrue(succeeded)
        let snapshot = try XCTUnwrap(LibraryBackupStore.latestValidSnapshot(in: backups))
        XCTAssertEqual(snapshot.catalog.frames.first?.customDisplayName, "Before freeze")
        // 결함 기록은 세션 전용이라 백업에도 sidecar가 없다(종료 시 이미지에 굽힘).
        XCTAssertNil(DefectSidecarFile.load(
            for: frame.id,
            in: snapshot.directoryURL.appendingPathComponent("defects", isDirectory: true)
        ))
        XCTAssertNil(DefectSidecarFile.load(for: frame.id, in: defects))
        XCTAssertTrue(LibraryCatalogHealthInspector.inspect(
            snapshot.catalog,
            defectDirectory: snapshot.directoryURL.appendingPathComponent("defects", isDirectory: true)
        ).canOpenSafely)
    }

    private func makeEdit(label: DefectEditLabel) -> DefectEditItem {
        DefectEditItem(
            edit: .brush([]),
            label: label,
            summaryKind: .brush,
            preview: [],
            baseSize: nil
        )
    }
}
