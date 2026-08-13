import XCTest
import Chromabase
import ScannerKit
@testable import negaflowApp

@MainActor
final class ImportDuplicateTests: XCTestCase {
    func testExactExistingAndWithinBatchDuplicatesAreSkippedInInputOrder() {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-import-dedup-\(UUID().uuidString)", isDirectory: true)
        let existing = folder.appendingPathComponent("existing.tiff")
        let first = folder.appendingPathComponent("first.dng")
        let second = folder.appendingPathComponent("second.jpg")

        let result = AppModel.filterDuplicateImports(
            [existing, first, first, second, existing],
            existingSourceURLs: [existing]
        )

        XCTAssertEqual(result.urls, [first, second])
        XCTAssertEqual(result.duplicateCount, 3)
    }

    func testDifferentPathsWithSameFilenameRemainDistinct() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-import-distinct-\(UUID().uuidString)", isDirectory: true)
        let first = root.appendingPathComponent("a/frame.tiff")
        let second = root.appendingPathComponent("b/frame.tiff")

        let result = AppModel.filterDuplicateImports([first, second], existingSourceURLs: [])

        XCTAssertEqual(result.urls, [first, second])
        XCTAssertEqual(result.duplicateCount, 0)
    }

    func testImportedFrameGetsExplicitUnassignedMembershipBeforeCatalogSave() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-import-roll-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("source.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 8, height: 6, to: sourceURL)
        let model = AppModel(
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )

        model.importImages(urls: [sourceURL])

        let frame = try XCTUnwrap(model.frames.first)
        XCTAssertEqual(model.frames.count, 1)
        XCTAssertEqual(model.rolls.count, 1)
        XCTAssertEqual(model.rolls[0].kind, .unassigned)
        XCTAssertEqual(model.rolls[0].frameIDs, [frame.id])
        XCTAssertEqual(model.rollID(containing: frame.id), LibraryRoll.unassignedID)

        model.librarySaveTask?.cancel()
        model.librarySaveTask = nil
        model.libraryPersistenceEnabled = true
        XCTAssertTrue(model.saveLibrary(synchronous: true))
        let persisted = try XCTUnwrap(
            LibraryCatalogFile.decode(try Data(contentsOf: model.libraryCatalogURL))?.rolls.only
        )
        let inMemory = try XCTUnwrap(model.rolls.only)
        XCTAssertEqual(persisted.id, inMemory.id)
        XCTAssertEqual(persisted.kind, inMemory.kind)
        XCTAssertEqual(persisted.frameIDs, inMemory.frameIDs)
        XCTAssertEqual(persisted.name, inMemory.name)
        XCTAssertEqual(persisted.filmType, inMemory.filmType)
        XCTAssertLessThan(abs(persisted.createdAt.timeIntervalSince(inMemory.createdAt)), 1)
    }

    func testImportDoesNotApplyScannerOrientationTemplateAfterImageIOOrientation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-import-orientation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("source.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 8, height: 6, to: sourceURL)
        let model = AppModel(
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )
        let scannerTemplate = ImageTransform(rotation: .deg90, flipHorizontal: true)
        model.nextScanOrientation = scannerTemplate

        model.importImages(urls: [sourceURL])

        XCTAssertEqual(model.frames.first?.imageTransform, .identity)
        XCTAssertEqual(model.nextScanOrientation, scannerTemplate)
    }

    func testImportPersistsSelectedDigitalBWProcessOnTheFrame() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-import-digital-bw-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("source.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 8, height: 6, to: sourceURL)
        let catalogURL = root.appendingPathComponent("library.json")
        let defectsURL = root.appendingPathComponent("defects", isDirectory: true)
        let backupsURL = root.appendingPathComponent("backups", isDirectory: true)
        let model = AppModel(
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: defectsURL,
            libraryBackupDirectoryURL: backupsURL
        )
        model.applyDevelopmentProcess(.digitalBW, to: nil)

        model.importImages(urls: [sourceURL])

        let frame = try XCTUnwrap(model.frames.first)
        XCTAssertEqual(frame.filmType, .bwPositive)
        XCTAssertEqual(frame.params.isDigitalSource, true)
        XCTAssertEqual(
            DevelopmentProcess(
                filmType: frame.filmType,
                isDigitalSource: frame.params.isDigitalSource
            ),
            .digitalBW
        )
        model.librarySaveTask?.cancel()
        model.librarySaveTask = nil
        model.libraryPersistenceEnabled = true
        XCTAssertTrue(model.saveLibrary(synchronous: true))
        model.libraryPersistenceEnabled = false

        let restoredModel = AppModel(
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: defectsURL,
            libraryBackupDirectoryURL: backupsURL
        )
        await restoredModel.restoreLibraryOnLaunch()
        defer {
            restoredModel.libraryPersistenceEnabled = false
            restoredModel.librarySaveTask?.cancel()
            restoredModel.librarySaveTask = nil
        }
        let restored = try XCTUnwrap(restoredModel.frames.first)
        XCTAssertEqual(restored.params.isDigitalSource, true)
        XCTAssertEqual(
            DevelopmentProcess(
                filmType: restored.filmType,
                isDigitalSource: restored.params.isDigitalSource
            ),
            .digitalBW
        )
    }

    func testAllFilmProcessesAndTargetsSurviveCatalogRestart() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-film-process-restart-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let catalogURL = root.appendingPathComponent("library.json")
        let defectsURL = root.appendingPathComponent("defects", isDirectory: true)
        let backupsURL = root.appendingPathComponent("backups", isDirectory: true)
        let processes: [DevelopmentProcess] = [.c41, .e6, .d76, .bwReversal]
        let targets: [DevelopTarget] = [.main, .print, .rescue, .hr]
        let sourceURLs = try processes.indices.map { index in
            let url = root.appendingPathComponent("source-\(index).tiff")
            try MockScannerBackend.writeSyntheticNegative(width: 8, height: 6, to: url)
            return url
        }
        let model = AppModel(
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: defectsURL,
            libraryBackupDirectoryURL: backupsURL
        )
        model.importImages(urls: sourceURLs)
        XCTAssertEqual(model.frames.count, processes.count)

        for (frame, selection) in zip(model.frames, zip(processes, targets)) {
            model.applyDevelopmentProcess(selection.0, to: frame)
            model.applyDevelopTarget(selection.1, to: frame)
        }
        model.librarySaveTask?.cancel()
        model.librarySaveTask = nil
        model.libraryPersistenceEnabled = true
        XCTAssertTrue(model.saveLibrary(synchronous: true))
        model.libraryPersistenceEnabled = false

        let restoredModel = AppModel(
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: defectsURL,
            libraryBackupDirectoryURL: backupsURL
        )
        await restoredModel.restoreLibraryOnLaunch()
        defer {
            restoredModel.libraryPersistenceEnabled = false
            restoredModel.librarySaveTask?.cancel()
            restoredModel.librarySaveTask = nil
        }

        let restoredByURL = Dictionary(
            uniqueKeysWithValues: restoredModel.frames.map { ($0.rawScanURL, $0) }
        )
        for (sourceURL, selection) in zip(sourceURLs, zip(processes, targets)) {
            let restored = try XCTUnwrap(restoredByURL[sourceURL])
            XCTAssertEqual(
                DevelopmentProcess(
                    filmType: restored.filmType,
                    isDigitalSource: restored.params.isDigitalSource
                ),
                selection.0
            )
            XCTAssertEqual(restored.params.developTarget, selection.1)
        }
    }

    func testImportDoesNotDevelopAutomaticallyByDefault() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-import-manual-develop-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("source.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 8, height: 6, to: sourceURL)
        let suiteName = "negaflow-import-manual-develop.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            presentationPreferencesStore: PresentationPreferencesStore(defaults: defaults),
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )
        model.activeWorkspaceModule = .library

        model.importImages(urls: [sourceURL])
        let frame = try XCTUnwrap(model.frames.first)
        if let seed = frame.initialThumbnailSeedTask {
            await seed.value
        }
        try await Task.sleep(for: .milliseconds(250))

        XCTAssertFalse(model.developsImportsAutomatically)
        XCTAssertFalse(frame.hasDevelopedOnce)
        XCTAssertNotNil(frame.rawPreviewImage)
        XCTAssertNil(frame.developedImage)
    }

    func testImportDevelopsAutomaticallyWhenPreferenceIsEnabled() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-import-auto-develop-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("source.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 8, height: 6, to: sourceURL)
        let suiteName = "negaflow-import-auto-develop.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            presentationPreferencesStore: PresentationPreferencesStore(defaults: defaults),
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )
        model.activeWorkspaceModule = .library
        model.developsImportsAutomatically = true

        model.importImages(urls: [sourceURL])
        let frame = try XCTUnwrap(model.frames.first)
        let deadline = Date().addingTimeInterval(5)
        while !frame.hasDevelopedOnce, Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertTrue(frame.hasDevelopedOnce)
        XCTAssertNotNil(frame.developedImage)
    }

    func testProgressAwareImportPublishesCompletedAndTotalCounts() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-import-progress-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let firstURL = root.appendingPathComponent("first.tiff")
        let secondURL = root.appendingPathComponent("second.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 8, height: 6, to: firstURL)
        try MockScannerBackend.writeSyntheticNegative(width: 8, height: 6, to: secondURL)
        let model = AppModel(
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: root.appendingPathComponent("backups", isDirectory: true)
        )

        await model.importImagesWithProgress(urls: [firstURL, secondURL])

        XCTAssertEqual(model.frames.count, 2)
        XCTAssertEqual(
            model.libraryImportProgressStore.progress,
            LibraryTaskProgress(completedCount: 2, totalCount: 2)
        )
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
