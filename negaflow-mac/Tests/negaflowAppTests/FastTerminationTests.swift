import XCTest
@testable import negaflowApp

/// 종료가 이미 디스크에 확인된 결함 기록을 다시 해시·저장하지 않고, 바뀐 것 없는 카탈로그를
/// 다시 쓰지 않는지 본다. 확정되지 않은 편집은 여전히 저장돼야 한다.
@MainActor
final class FastTerminationTests: XCTestCase {
    @MainActor
    private struct Fixture {
        let root: URL
        let model: AppModel
        let frame: ScanFrame
        var sidecarURL: URL { DefectSidecarFile.url(for: frame.id, in: model.libraryDefectDirectoryURL) }
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-fast-termination-\(UUID().uuidString)", isDirectory: true
        )
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FastTerminationTests-\(UUID().uuidString)"))
        let schedule = LibraryBackupScheduleStore(defaults: defaults)
        schedule.schedule = .manual
        let model = AppModel(
            backupScheduleStore: schedule,
            libraryCatalogURL: root.appendingPathComponent("library.sqlite"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )
        let roll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Fast quit roll", filmType: .colorNegative, activate: true
        ))
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/offline/fast-quit.tiff"),
            filmType: .colorNegative
        )
        frame.establishLibraryWorkflowBaselineIfNeeded()
        frame.defectEdits = [DefectEditItem(
            edit: .brush([DefectStroke(points: [CGPoint(x: 0.2, y: 0.3)], thickness: 0.05)]),
            label: .brush(strokeCount: 1),
            summaryKind: .classBreakdown(DefectClassBreakdown(counts: [], meanConfidence: 0)),
            preview: [], baseSize: nil
        )]
        model.frames = [frame]
        XCTAssertTrue(model.assignNewPersistentFrames([frame], toRollID: roll.id))
        model.libraryPersistenceEnabled = true
        XCTAssertNotNil(model.refreshDefectRecipeState(frame, advanceRevision: true, persist: true))
        DefectSidecarFile.flushSync()
        model.librarySaveTask?.cancel()
        model.librarySaveTask = nil
        return Fixture(root: root, model: model, frame: frame)
    }

    private func tearDown(_ fixture: Fixture) {
        fixture.model.libraryPersistenceEnabled = false
        fixture.model.librarySaveTask?.cancel()
        fixture.model.sessionBackupTask?.cancel()
        try? FileManager.default.removeItem(at: fixture.root)
    }

    private func modificationDate(_ url: URL) throws -> Date {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
    }

    func testCommittedRecipeIsRecognizedOnlyWhileDiskMatches() throws {
        let fixture = try makeFixture()
        defer { tearDown(fixture) }
        let model = fixture.model
        let frame = fixture.frame
        XCTAssertTrue(model.isDefectRecipeCommitted(frame))

        frame.defectGestureRecipeAdvanced = true
        XCTAssertFalse(model.isDefectRecipeCommitted(frame))
        frame.defectGestureRecipeAdvanced = false

        let identity = frame.defectRecipeIdentity
        frame.defectRecipeIdentity = nil
        XCTAssertFalse(model.isDefectRecipeCommitted(frame))
        frame.defectRecipeIdentity = identity
        XCTAssertTrue(model.isDefectRecipeCommitted(frame))

        // 디스크 기록이 바깥에서 바뀌면 확정으로 보지 않는다.
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000_000)],
            ofItemAtPath: fixture.sidecarURL.path
        )
        XCTAssertFalse(model.isDefectRecipeCommitted(frame))
    }

    func testTerminationCommitsAtOnceWhenRecipesAreAlreadyStored() throws {
        let fixture = try makeFixture()
        defer { tearDown(fixture) }
        let model = fixture.model
        let revision = fixture.frame.defectRecipeRevision
        let sidecarWrittenAt = try modificationDate(fixture.sidecarURL)
        var completions: [LibraryTerminationCommitCompletion] = []
        var replies: [Bool] = []

        let decision = model.beginApplicationTermination(
            scheduleCommit: { _, _, _, _, completion in completions.append(completion) },
            completion: { replies.append($0) }
        )

        // 굽기 단계를 건너뛰어 커밋이 같은 호출 안에서 바로 예약된다.
        XCTAssertEqual(decision, .terminateLater)
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(fixture.frame.defectRecipeRevision, revision)
        XCTAssertEqual(try modificationDate(fixture.sidecarURL), sidecarWrittenAt)
        try XCTUnwrap(completions.first)(.success(()))
        XCTAssertEqual(replies, [true])
    }

    func testTerminationStillStoresOpenGestureRecipe() async throws {
        let fixture = try makeFixture()
        defer { tearDown(fixture) }
        let model = fixture.model
        let frame = fixture.frame
        let revision = frame.defectRecipeRevision
        frame.defectEdits[0].strength = 0.4
        frame.defectGestureRecipeAdvanced = true
        let scheduled = expectation(description: "종료 커밋 예약")
        var completions: [LibraryTerminationCommitCompletion] = []
        var replies: [Bool] = []

        let decision = model.beginApplicationTermination(
            scheduleCommit: { _, _, _, _, completion in
                completions.append(completion)
                scheduled.fulfill()
            },
            completion: { replies.append($0) }
        )

        XCTAssertEqual(decision, .terminateLater)
        XCTAssertTrue(completions.isEmpty)
        await fulfillment(of: [scheduled], timeout: 5)
        XCTAssertEqual(frame.defectRecipeRevision, revision + 1)
        XCTAssertTrue(model.isDefectRecipeCommitted(frame))
        guard case .loaded(.currentV2(_, let stored)) = DefectSidecarFile.read(
            for: frame.id, in: model.libraryDefectDirectoryURL
        ) else { return XCTFail("결함 기록이 저장되지 않았다") }
        XCTAssertEqual(stored.identity, frame.defectRecipeIdentity)
        XCTAssertEqual(stored.items.first?.strength, 0.4)
        try XCTUnwrap(completions.first)(.success(()))
        XCTAssertEqual(replies, [true])
    }

    func testUnchangedSQLiteCommitLeavesVerifiedFileAlone() throws {
        let fixture = try makeFixture()
        defer { tearDown(fixture) }
        let model = fixture.model
        let url = model.libraryCatalogURL
        let catalog = try XCTUnwrap(model.currentLibraryCatalogSnapshot())
        guard case .success = LibraryCatalogFile.commitAndVerify(
            catalog, to: url, defectDirectory: model.libraryDefectDirectoryURL, catalogSafetyValidated: true
        ) else { return XCTFail("첫 커밋 실패") }
        let committedAt = try modificationDate(url)

        // 쓸 것이 없으면 폴더에 아무것도 만들지 않는다 — 롤백 사본조차. 읽기 전용 폴더에서도 승인된다.
        let fileManager = FileManager.default
        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.root.path)
        let unchanged = LibraryCatalogFile.commitAndVerify(
            catalog, to: url, defectDirectory: model.libraryDefectDirectoryURL, catalogSafetyValidated: true
        )
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.root.path)
        guard case .success = unchanged else { return XCTFail("무변경 커밋이 파일을 다시 쓰려 했다") }
        XCTAssertEqual(try modificationDate(url), committedAt)

        // 내용이 바뀌면 그대로 쓰고 검증한다.
        fixture.frame.customDisplayName = "changed"
        let changed = try XCTUnwrap(model.currentLibraryCatalogSnapshot())
        guard case .success = LibraryCatalogFile.commitAndVerify(
            changed, to: url, defectDirectory: model.libraryDefectDirectoryURL, catalogSafetyValidated: true
        ) else { return XCTFail("변경 커밋 실패") }
        XCTAssertEqual(LibraryCatalogFile.loadPrimary(from: url)?.frames.first?.customDisplayName, "changed")
    }
}
