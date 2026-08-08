import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import negaflowApp

final class SourceRelinkTests: XCTestCase {

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    func testFolderPlanMapsRelativeFilesAndKeepsUnresolvedSources() {
        let oldRoot = URL(fileURLWithPath: "/Volumes/Old/Roll", isDirectory: true)
        let newRoot = URL(fileURLWithPath: "/Volumes/New/Archive/Roll", isDirectory: true)
        let first = oldRoot.appendingPathComponent("a.tiff")
        let second = oldRoot.appendingPathComponent("nested/b.tiff")
        let missing = oldRoot.appendingPathComponent("missing.tiff")
        let outside = URL(fileURLWithPath: "/Volumes/Old/Other/c.tiff")
        let readable = Set([
            newRoot.appendingPathComponent("a.tiff").path,
            newRoot.appendingPathComponent("nested/b.tiff").path,
        ])

        let plan = SourceRelinkPlanner.folderPlan(
            oldFolderURL: oldRoot,
            newFolderURL: newRoot,
            sourceURLs: [first, second, missing, first, outside],
            isReadable: { readable.contains($0.path) }
        )

        XCTAssertEqual(plan.mappings.map(\.oldSourceURL), [first, second])
        XCTAssertEqual(
            plan.mappings.map(\.newSourceURL),
            [newRoot.appendingPathComponent("a.tiff"),
             newRoot.appendingPathComponent("nested/b.tiff")]
        )
        XCTAssertEqual(plan.unresolvedSourceURLs, [missing])
        XCTAssertFalse(plan.isComplete)
    }

    func testFolderPlanRelocatesExistingInfraredCompanionOnly() {
        let oldRoot = URL(fileURLWithPath: "/Volumes/Old/Roll", isDirectory: true)
        let newRoot = URL(fileURLWithPath: "/Volumes/New/Roll", isDirectory: true)
        let infrared = oldRoot.appendingPathComponent("ir/frame-ir.tiff")
        let relocated = newRoot.appendingPathComponent("ir/frame-ir.tiff")
        let plan = SourceRelinkPlan(
            mappings: [],
            oldFolderURL: oldRoot,
            newFolderURL: newRoot
        )

        XCTAssertEqual(
            SourceRelinkPlanner.relocatedCompanionURL(
                infrared,
                using: plan,
                fileExists: { $0.path == relocated.path }
            ),
            relocated
        )
        XCTAssertEqual(
            SourceRelinkPlanner.relocatedCompanionURL(
                infrared,
                using: plan,
                fileExists: { _ in false }
            ),
            infrared
        )
    }

    func testPersistentBookmarkResolvesFileMovedOnSameVolume() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-bookmark-\(UUID().uuidString)", isDirectory: true)
        let movedDirectory = directory.appendingPathComponent("moved", isDirectory: true)
        let original = directory.appendingPathComponent("source.tiff")
        let moved = movedDirectory.appendingPathComponent("source-renamed.tiff")
        try FileManager.default.createDirectory(at: movedDirectory, withIntermediateDirectories: true)
        try Data("bookmark".utf8).write(to: original)
        defer { try? FileManager.default.removeItem(at: directory) }

        let bookmark = try XCTUnwrap(SourceBookmark.create(for: original))
        try FileManager.default.moveItem(at: original, to: moved)

        let resolved = SourceBookmark.resolve(bookmark, fallbackURL: original)

        XCTAssertEqual(resolved.url.standardizedFileURL.path, moved.standardizedFileURL.path)
        XCTAssertNotNil(resolved.bookmarkData)
    }

    @MainActor
    func testCatalogRecordUsesBookmarkToRestoreMovedSource() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-catalog-bookmark-\(UUID().uuidString)", isDirectory: true)
        let movedDirectory = directory.appendingPathComponent("moved", isDirectory: true)
        let original = directory.appendingPathComponent("source.tiff")
        let moved = movedDirectory.appendingPathComponent("source.tiff")
        try FileManager.default.createDirectory(at: movedDirectory, withIntermediateDirectories: true)
        try Data("catalog bookmark".utf8).write(to: original)
        defer { try? FileManager.default.removeItem(at: directory) }
        let frame = ScanFrame(scanIndex: 1, rawScanURL: original, filmType: .colorNegative)
        let record = LibraryFrameRecord(frame: frame)
        try FileManager.default.moveItem(at: original, to: moved)

        let restored = record.makeFrame(presets: [])

        XCTAssertEqual(restored.rawScanURL.standardizedFileURL.path, moved.standardizedFileURL.path)
        XCTAssertEqual(restored.id, frame.id)
    }

    @MainActor
    func testRelinkUpdatesEveryFrameSharingSourceAndInvalidatesDerivedCaches() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-relink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let oldRaw = directory.appendingPathComponent("missing.png")
        let newRaw = directory.appendingPathComponent("found.png")
        let infrared = directory.appendingPathComponent("frame-ir.tiff")
        try Self.writePNG(to: newRaw)
        try Data("ir".utf8).write(to: infrared)

        let original = ScanFrame(
            scanIndex: 1,
            rawScanURL: oldRaw,
            filmType: .colorNegative,
            infraredScanURL: infrared
        )
        let cleaned = CleanedRawCacheFile.makeBuildURL(frameID: original.id)
        defer { try? FileManager.default.removeItem(at: cleaned) }
        try Data("cache".utf8).write(to: cleaned)
        original.params.exposure = 0.65
        original.hasDevelopedOnce = true
        original.baseRGB = SIMD3(0.8, 0.6, 0.4)
        original.cleanedRawDiskURL = cleaned
        original.cleanedRawEditCount = 2
        let copy = original.makeVirtualCopy(copyNumber: 1)
        let model = AppModel()
        model.frames = [original, copy]

        let outcome = model.applySourceRelink(
            SourceRelinkPlan(mappings: [
                .init(oldSourceURL: oldRaw, newSourceURL: newRaw)
            ]),
            reprocess: false
        )

        XCTAssertEqual(outcome.frameCount, 2)
        XCTAssertEqual(outcome.sourceCount, 1)
        XCTAssertEqual(original.rawScanURL, newRaw)
        XCTAssertEqual(copy.rawScanURL, newRaw)
        XCTAssertEqual(original.infraredScanURL, infrared)
        XCTAssertEqual(copy.infraredScanURL, infrared)
        XCTAssertEqual(original.params.exposure, 0.65, accuracy: 1e-12)
        XCTAssertFalse(original.hasDevelopedOnce)
        XCTAssertNil(original.baseRGB)
        XCTAssertNil(copy.baseRGB)
        XCTAssertEqual(original.sourceLocationRevision, 1)
        XCTAssertEqual(copy.sourceLocationRevision, 1)
        XCTAssertNil(original.cleanedRawDiskURL)
        XCTAssertEqual(original.cleanedRawEditCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cleaned.path))
        XCTAssertNotNil(original.rawScanBookmarkData)
        let expectedMetadata = SourceMetadataReader.read(from: newRaw)
        XCTAssertEqual(original.sourceMetadata, expectedMetadata)
        XCTAssertEqual(copy.sourceMetadata, expectedMetadata)
        XCTAssertEqual(original.sourceMetadata, copy.sourceMetadata)
    }

    @MainActor
    func testSameByteRelinkPersistsUnboundRecipeAndInvalidatesAllCleanedRawProof() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-relink-identity-\(UUID().uuidString)", isDirectory: true)
        let defectDirectory = directory.appendingPathComponent("defects", isDirectory: true)
        let catalogURL = directory.appendingPathComponent("library.json")
        let backupDirectory = directory.appendingPathComponent("backups", isDirectory: true)
        let oldRaw = directory.appendingPathComponent("old.png")
        let newRaw = directory.appendingPathComponent("new.png")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.writePNG(to: oldRaw)
        try FileManager.default.copyItem(at: oldRaw, to: newRaw)

        let sessionID = UUID()
        let jobID = UUID()
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: oldRaw,
            filmType: .colorNegative,
            sourceMetadata: SourceMetadataReader.read(from: oldRaw),
            scanSessionID: sessionID,
            scanJobID: jobID
        )
        let item = DefectEditItem(
            edit: .brush([DefectStroke(
                points: [CGPoint(x: 0.25, y: 0.5)],
                thickness: 0.02
            )]),
            label: .brush(strokeCount: 1),
            summaryKind: .classBreakdown(DefectClassBreakdown(counts: [], meanConfidence: 0)),
            preview: [],
            baseSize: nil
        )
        let sourceIdentity = try AppModel.defectSourceIdentity(for: oldRaw)
        // stat 기반 identity에서는 바이트가 같아도 사본은 다른 identity다 — relink는
        // 어느 쪽이든 보수적으로 unbind + 전체 무효화로 수렴한다.
        XCTAssertNotEqual(try AppModel.defectSourceIdentity(for: newRaw), sourceIdentity)
        let boundSnapshot = try DefectRecipeSnapshot(
            frameID: frame.id,
            revision: 4,
            sourceIdentity: sourceIdentity,
            items: [DefectEditItemRecord(item: item)]
        )
        frame.defectEdits = [item]
        frame.defectRecipeRevision = boundSnapshot.identity.revision
        frame.defectRecipeIdentity = boundSnapshot.identity
        frame.establishLibraryWorkflowBaselineIfNeeded()
        var workflow = try XCTUnwrap(frame.libraryWorkflowTrackingState)
        workflow.defectReviewTracking = LibraryDefectReviewTracking(
            coverage: .tracked,
            currentRecipeRevision: boundSnapshot.identity.revision,
            currentRecipeSHA256: boundSnapshot.identity.recipeSHA256,
            currentSourceIdentitySHA256: sourceIdentity.sha256,
            reviewedRecipeRevision: boundSnapshot.identity.revision,
            reviewedRecipeSHA256: boundSnapshot.identity.recipeSHA256,
            reviewedSourceIdentitySHA256: sourceIdentity.sha256
        )
        frame.libraryWorkflowTrackingState = workflow

        _ = try DefectSidecarFile.write(boundSnapshot, in: defectDirectory)
        let cacheURL = CleanedRawCacheFile.makeBuildURL(frameID: frame.id)
        defer {
            try? FileManager.default.removeItem(at: cacheURL)
        }
        try Data("cleaned raw cache".utf8).write(to: cacheURL)
        frame.cleanedRawImage = try Self.makeCGImage()
        frame.cleanedRawMemoryIdentity = boundSnapshot.identity
        frame.cleanedRawDiskURL = cacheURL
        frame.cleanedRawDiskIdentity = boundSnapshot.identity
        frame.cleanedRawEditCount = 1
        frame.cleanedRawPreviousImage = try Self.makeCGImage()
        frame.cleanedRawPreviousEditCount = 0
        frame.cleanedRawPreviousIdentity = boundSnapshot.identity
        frame.hasDevelopedOnce = true
        frame.isRemovingDefects = true

        let cleanTask = Task<Void, Never> {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
        }
        defer { cleanTask.cancel() }
        frame.cleanRawTask = cleanTask
        let initialDevelopRevision = frame.developRevision
        let initialCleanRevision = frame.cleanRawRevision
        let model = AppModel(
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: defectDirectory,
            libraryBackupDirectoryURL: backupDirectory
        )
        model.frames = [frame]
        model.libraryPersistenceEnabled = true
        defer {
            model.libraryPersistenceEnabled = false
            model.librarySaveTask?.cancel()
        }

        let outcome = model.applySourceRelink(
            SourceRelinkPlan(mappings: [
                .init(oldSourceURL: oldRaw, newSourceURL: newRaw)
            ]),
            reprocess: false
        )
        DefectSidecarFile.flushSync()

        XCTAssertEqual(outcome.frameCount, 1)
        XCTAssertEqual(outcome.sourceCount, 1)
        XCTAssertEqual(frame.rawScanURL, newRaw)
        XCTAssertEqual(frame.scanSessionID, sessionID)
        XCTAssertEqual(frame.scanJobID, jobID)
        XCTAssertEqual(frame.developRevision, initialDevelopRevision + 1)
        XCTAssertEqual(frame.cleanRawRevision, initialCleanRevision + 1)
        XCTAssertTrue(cleanTask.isCancelled)
        XCTAssertNil(frame.cleanRawTask)
        XCTAssertFalse(frame.isRemovingDefects)
        XCTAssertNil(frame.cleanedRawImage)
        XCTAssertNil(frame.cleanedRawMemoryIdentity)
        XCTAssertNil(frame.cleanedRawDiskURL)
        XCTAssertNil(frame.cleanedRawDiskIdentity)
        XCTAssertNil(frame.cleanedRawPreviousImage)
        XCTAssertNil(frame.cleanedRawPreviousIdentity)
        XCTAssertFalse(frame.hasDevelopedOnce)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertEqual(frame.defectEdits.count, 1)
        let relinkedIdentity = try XCTUnwrap(frame.defectRecipeIdentity)
        XCTAssertEqual(relinkedIdentity.revision, boundSnapshot.identity.revision + 1)
        XCTAssertEqual(relinkedIdentity.recipeSHA256, boundSnapshot.identity.recipeSHA256)
        XCTAssertNil(relinkedIdentity.sourceIdentity)

        // 기록은 디스크에 남지 않는다 — relink 후에도 메모리 recipe만 유지된다.
        XCTAssertEqual(
            frame.defectEdits.map(DefectEditItemRecord.init(item:)),
            [DefectEditItemRecord(item: item)]
        )
        let review = try XCTUnwrap(frame.libraryWorkflowTrackingState).defectReviewTracking
        XCTAssertEqual(review.coverage, .tracked)
        XCTAssertNil(review.currentRecipeRevision)
        XCTAssertNil(review.currentRecipeSHA256)
        XCTAssertNil(review.currentSourceIdentitySHA256)
        XCTAssertNil(review.reviewedRecipeRevision)
        XCTAssertNil(review.reviewedRecipeSHA256)
        XCTAssertNil(review.reviewedSourceIdentitySHA256)
    }

        @MainActor
    func testRelinkFamilyPreflightDoesNotPartiallyUnbindEarlierFrame() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-relink-family-preflight-\(UUID().uuidString)", isDirectory: true)
        let oldRaw = directory.appendingPathComponent("old.png")
        let newRaw = directory.appendingPathComponent("new.png")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.writePNG(to: oldRaw)
        try FileManager.default.copyItem(at: oldRaw, to: newRaw)

        let original = ScanFrame(
            scanIndex: 1,
            rawScanURL: oldRaw,
            filmType: .colorNegative,
            sourceMetadata: SourceMetadataReader.read(from: oldRaw)
        )
        let copy = original.makeVirtualCopy(copyNumber: 1)
        let item = DefectEditItem(
            edit: .brush([DefectStroke(
                points: [CGPoint(x: 0.3, y: 0.4)],
                thickness: 0.02
            )]),
            label: .guided(count: 1),
            summaryKind: .classBreakdown(DefectClassBreakdown(counts: [], meanConfidence: 0)),
            preview: [],
            baseSize: nil
        )
        original.defectEdits = [item]
        copy.defectEdits = [item]
        let sourceIdentity = try AppModel.defectSourceIdentity(for: oldRaw)
        let originalSnapshot = try DefectRecipeSnapshot(
            frameID: original.id,
            revision: 1,
            sourceIdentity: sourceIdentity,
            items: [DefectEditItemRecord(item: item)]
        )
        let copySnapshot = try DefectRecipeSnapshot(
            frameID: copy.id,
            revision: UInt64.max,
            sourceIdentity: sourceIdentity,
            items: [DefectEditItemRecord(item: item)]
        )
        original.defectRecipeRevision = originalSnapshot.identity.revision
        original.defectRecipeIdentity = originalSnapshot.identity
        copy.defectRecipeRevision = copySnapshot.identity.revision
        copy.defectRecipeIdentity = copySnapshot.identity

        let model = AppModel()
        model.libraryPersistenceEnabled = false
        model.frames = [original, copy]

        let outcome = model.applySourceRelink(
            SourceRelinkPlan(mappings: [
                .init(oldSourceURL: oldRaw, newSourceURL: newRaw),
            ]),
            reprocess: false
        )

        XCTAssertEqual(outcome.frameCount, 0)
        XCTAssertEqual(outcome.sourceCount, 0)
        XCTAssertEqual(original.rawScanURL, oldRaw)
        XCTAssertEqual(copy.rawScanURL, oldRaw)
        XCTAssertEqual(original.defectRecipeIdentity, originalSnapshot.identity)
        XCTAssertEqual(original.defectRecipeRevision, 1)
        XCTAssertEqual(copy.defectRecipeIdentity, copySnapshot.identity)
        XCTAssertEqual(copy.defectRecipeRevision, UInt64.max)
    }

    @MainActor
    func testMetadataMismatchPreservesVirtualFamilyURLsCachesAndImmutableSnapshots() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-relink-mismatch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let oldRaw = directory.appendingPathComponent("original.png")
        let mismatchedRaw = directory.appendingPathComponent("different.png")
        try Self.writePNG(to: oldRaw, width: 2, height: 2)
        try Self.writePNG(to: mismatchedRaw, width: 3, height: 2)
        let originalMetadata = SourceMetadataReader.read(from: oldRaw)
        let original = ScanFrame(
            scanIndex: 1,
            rawScanURL: oldRaw,
            filmType: .colorNegative,
            sourceKind: .importedFile,
            sourcePixelWidth: originalMetadata.pixelWidth,
            sourcePixelHeight: originalMetadata.pixelHeight,
            sourceResolutionDPI: originalMetadata.resolutionDPI,
            sourceBitDepth: originalMetadata.bitsPerColorSample,
            sourceMetadata: originalMetadata
        )
        original.hasDevelopedOnce = true
        original.cleanedRawEditCount = 2
        let originalCache = CleanedRawCacheFile.makeBuildURL(frameID: original.id)
        defer { try? FileManager.default.removeItem(at: originalCache) }
        try Data("original cache".utf8).write(to: originalCache)
        original.cleanedRawDiskURL = originalCache

        let copy = original.makeVirtualCopy(copyNumber: 1)
        copy.hasDevelopedOnce = true
        copy.cleanedRawEditCount = 2
        let copyCache = CleanedRawCacheFile.makeBuildURL(frameID: copy.id)
        defer { try? FileManager.default.removeItem(at: copyCache) }
        try Data("copy cache".utf8).write(to: copyCache)
        copy.cleanedRawDiskURL = copyCache
        let model = AppModel()
        model.frames = [original, copy]

        let outcome = model.applySourceRelink(
            SourceRelinkPlan(mappings: [
                .init(oldSourceURL: oldRaw, newSourceURL: mismatchedRaw)
            ]),
            reprocess: false
        )

        XCTAssertEqual(outcome.frameCount, 0)
        XCTAssertEqual(outcome.sourceCount, 0)
        XCTAssertEqual(original.rawScanURL, oldRaw)
        XCTAssertEqual(copy.rawScanURL, oldRaw)
        XCTAssertEqual(original.sourceMetadata, originalMetadata)
        XCTAssertEqual(copy.sourceMetadata, originalMetadata)
        XCTAssertEqual(original.sourceMetadata, copy.sourceMetadata)
        XCTAssertEqual(original.cleanedRawDiskURL, originalCache)
        XCTAssertEqual(copy.cleanedRawDiskURL, copyCache)
        XCTAssertEqual(original.cleanedRawEditCount, 2)
        XCTAssertEqual(copy.cleanedRawEditCount, 2)
        XCTAssertTrue(original.hasDevelopedOnce)
        XCTAssertTrue(copy.hasDevelopedOnce)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalCache.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copyCache.path))
    }

    @MainActor
    func testCompleteFolderRelinkPreservesRegisteredFolderIdentity() {
        let oldFolder = LibraryFolder(
            id: UUID(),
            url: URL(fileURLWithPath: "/Volumes/Old/Roll", isDirectory: true),
            addedAt: Date(timeIntervalSince1970: 123)
        )
        let newFolder = URL(fileURLWithPath: "/Volumes/New/Roll", isDirectory: true)
        let model = AppModel()
        model.libraryFolders = [oldFolder]

        _ = model.applySourceRelink(
            SourceRelinkPlan(
                mappings: [],
                oldFolderURL: oldFolder.url,
                newFolderURL: newFolder
            ),
            reprocess: false
        )

        XCTAssertEqual(model.libraryFolders.count, 1)
        XCTAssertEqual(model.libraryFolders[0].id, oldFolder.id)
        XCTAssertEqual(model.libraryFolders[0].addedAt, oldFolder.addedAt)
        XCTAssertEqual(model.libraryFolders[0].url, newFolder)
    }

    @MainActor
    func testRefreshLibraryShortcutRefreshesSourcesWithoutStartingScannerDetection() {
        let model = AppModel()
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-offline-\(UUID().uuidString).tiff"),
            filmType: .colorNegative
        )
        model.frames = [frame]
        let revision = model.sourceAvailabilityRevision

        model.performWorkflowShortcutAction(.refreshLibrary)

        XCTAssertEqual(model.sourceAvailabilityRevision, revision + 1)
        XCTAssertFalse(model.isDetecting)
        XCTAssertEqual(
            model.statusMessage,
            model.text(AppLocalizedPhrase.libraryRefreshStatusFormat, 0, 0, 1)
        )
    }

    @MainActor
    func testRefreshLibraryImportsNewFilesOnceAndNeverRemovesMissingRecords() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-library-refresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("new.png")
        try Self.writePNG(to: imageURL)
        let missing = ScanFrame(
            scanIndex: 1,
            rawScanURL: directory.appendingPathComponent("missing.tiff"),
            filmType: .colorNegative
        )
        let model = AppModel()
        model.frames = [missing]
        model.libraryFolders = [LibraryFolder(url: directory)]

        model.refreshLibrary()
        XCTAssertEqual(model.frames.count, 2)
        XCTAssertTrue(model.frames.contains(where: { $0 === missing }))
        XCTAssertEqual(model.frames.filter { $0.rawScanURL == imageURL }.count, 1)

        model.refreshLibrary()
        XCTAssertEqual(model.frames.count, 2)
        XCTAssertEqual(model.frames.filter { $0.rawScanURL == imageURL }.count, 1)
    }

    @MainActor
    func testFileSystemSyncRelinksFinderMovedFileWithoutCreatingDuplicateFrame() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-file-sync-\(UUID().uuidString)", isDirectory: true)
        let sourceFolder = directory.appendingPathComponent("Source", isDirectory: true)
        let destinationFolder = directory.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = sourceFolder.appendingPathComponent("frame.png")
        let destination = destinationFolder.appendingPathComponent("frame.png")
        try Self.writePNG(to: source)
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: source,
            filmType: .colorNegative,
            sourceKind: .importedFile,
            sourceMetadata: SourceMetadataReader.read(from: source)
        )
        let model = AppModel()
        model.frames = [frame]
        model.libraryFolders = [
            LibraryFolder(url: sourceFolder),
            LibraryFolder(url: destinationFolder),
        ]

        try FileManager.default.moveItem(at: source, to: destination)
        await model.synchronizeLibraryAfterFileSystemChanges(
            in: [sourceFolder, destinationFolder]
        )

        XCTAssertEqual(model.frames.count, 1)
        XCTAssertEqual(frame.rawScanURL.standardizedFileURL, destination.standardizedFileURL)
        XCTAssertEqual(
            model.libraryFolders.map { $0.url.standardizedFileURL },
            [sourceFolder.standardizedFileURL, destinationFolder.standardizedFileURL]
        )
    }

    @MainActor
    func testFileSystemSyncPreservesRegisteredFolderIdentityAfterFinderRename() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-folder-sync-\(UUID().uuidString)", isDirectory: true)
        let originalFolder = directory.appendingPathComponent("Original", isDirectory: true)
        let renamedFolder = directory.appendingPathComponent("Renamed", isDirectory: true)
        try FileManager.default.createDirectory(at: originalFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = originalFolder.appendingPathComponent("frame.png")
        let renamed = renamedFolder.appendingPathComponent("frame.png")
        try Self.writePNG(to: original)
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: original,
            filmType: .colorNegative,
            sourceKind: .importedFile,
            sourceMetadata: SourceMetadataReader.read(from: original)
        )
        let folder = LibraryFolder(
            id: UUID(),
            url: originalFolder,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let model = AppModel()
        model.frames = [frame]
        model.libraryFolders = [folder]

        try FileManager.default.moveItem(at: originalFolder, to: renamedFolder)
        await model.synchronizeLibraryAfterFileSystemChanges(in: [originalFolder])

        XCTAssertEqual(model.frames.count, 1)
        XCTAssertEqual(frame.rawScanURL.standardizedFileURL, renamed.standardizedFileURL)
        XCTAssertEqual(model.libraryFolders.count, 1)
        XCTAssertEqual(model.libraryFolders[0].id, folder.id)
        XCTAssertEqual(model.libraryFolders[0].addedAt, folder.addedAt)
        XCTAssertEqual(model.libraryFolders[0].url.standardizedFileURL, renamedFolder.standardizedFileURL)
    }

    /// 폴더 감시는 이미 가져온 원본의 이동만 따라간다. 같은 폴더에 새로 생긴 파일은
    /// 사용자가 명시적으로 가져오기 전까지 라이브러리에 들어오지 않는다.
    @MainActor
    func testFileSystemSyncDoesNotImportNewFilesFromChangedFolder() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-new-file-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let existingURL = directory.appendingPathComponent("existing.png")
        let newURL = directory.appendingPathComponent("new.png")
        try Self.writePNG(to: existingURL)
        let existing = ScanFrame(
            scanIndex: 1,
            rawScanURL: existingURL,
            filmType: .colorNegative,
            sourceKind: .importedFile,
            sourceMetadata: SourceMetadataReader.read(from: existingURL)
        )
        let model = AppModel()
        model.frames = [existing]
        model.libraryFolders = [LibraryFolder(url: directory)]
        try Self.writePNG(to: newURL)

        let statusBefore = model.statusMessage
        let availabilityRevisionBefore = model.sourceAvailabilityRevision

        await model.synchronizeLibraryAfterFileSystemChanges(in: [directory])

        XCTAssertEqual(model.frames.count, 1)
        XCTAssertEqual(model.frames.filter { $0.rawScanURL == existingURL }.count, 1)
        XCTAssertTrue(model.frames.filter { $0.rawScanURL == newURL }.isEmpty)
        // 우리 원본이 그대로면 폴더 이벤트는 아무 일도 하지 않는다. iCloud 가 같은 폴더로
        // 수백 장을 내려받는 동안 이벤트마다 전체 가용성을 다시 재면 UI 가 멈춘다.
        XCTAssertEqual(model.statusMessage, statusBefore)
        XCTAssertEqual(model.sourceAvailabilityRevision, availabilityRevisionBefore)
    }

    private static func writePNG(
        to url: URL,
        width: Int = 2,
        height: Int = 2
    ) throws {
        let image = try makeCGImage(width: width, height: height)
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private static func makeCGImage(
        width: Int = 2,
        height: Int = 2
    ) throws -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}
