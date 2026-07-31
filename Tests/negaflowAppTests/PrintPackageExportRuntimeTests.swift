import Chromabase
import ScannerKit
import XCTest
@testable import negaflowApp

@MainActor
final class PrintPackageExportRuntimeTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-print-runtime-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "negaflow-print-runtime-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        if let defaults, let suiteName { defaults.removePersistentDomain(forName: suiteName) }
        root = nil
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    func testCompositeExportCommitsUniqueContributorEventsWithoutSingleSourcePairs() async throws {
        let exportRoot = root.appendingPathComponent("Exports", isDirectory: true)
        let diskStore = DiskStorageStore(defaults: defaults)
        diskStore.exportPath = exportRoot.path
        let printStore = PrintWorkspaceSettingsStore(defaults: defaults)
        printStore.layoutMode = .contactSheet
        printStore.paperSize = .fourBySix
        printStore.orientation = .landscape
        printStore.marginMM = 5
        printStore.packageSettings = PrintPackageSettings(
            mode: .contactSheet,
            contactRows: 1,
            contactColumns: 2,
            horizontalSpacingMM: 2,
            verticalSpacingMM: 0,
            captionMode: .fileName
        )
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            printWorkspaceSettingsStore: printStore,
            diskStorageStore: diskStore,
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )
        try setSyntheticPrinterOutputProfile(on: model)
        await model.restoreLibraryOnLaunch()
        let first = try makeFrame(index: 1, width: 24, height: 16)
        let second = try makeFrame(index: 2, width: 16, height: 24)
        model.frames = [first, second]
        XCTAssertTrue(model.assignNewPersistentFrames([first, second]))
        first.hasDevelopedOnce = true
        second.hasDevelopedOnce = true
        first.displayPixelSize = CGSize(width: 24, height: 16)
        second.displayPixelSize = CGSize(width: 16, height: 24)
        model.updateInteractionScope([first.id, second.id])
        model.selectedFrameIDs = [first.id, second.id]
        model.exportFormat = .png
        model.exportDPI = 72
        model.exportWriteSidecar = true
        model.exportWriteMainFlatMaster = true
        model.exportWriteOriginalRaw = true
        XCTAssertTrue(model.saveLibrary(synchronous: true))

        model.exportPrintSelectionToFolder(
            settings: printStore.compositionSettings(dpi: 72)
        )
        XCTAssertEqual(model.printPackageExportProgress?.completedPages, 0)
        XCTAssertEqual(model.printPackageExportProgress?.totalPages, 1)
        XCTAssertEqual(model.printPackageExportProgress?.percent, 0)
        try await waitForPackageExport(model)
        XCTAssertNil(model.printPackageExportProgress)

        let outputFiles = regularFiles(below: exportRoot)
        let imageFiles = outputFiles.filter { $0.pathExtension == "png" }
        XCTAssertEqual(imageFiles.count, 1)
        XCTAssertFalse(outputFiles.contains { $0.lastPathComponent.contains("main-flat") })
        XCTAssertFalse(outputFiles.contains { $0.lastPathComponent.contains("original") })
        XCTAssertFalse(outputFiles.contains { ["json", "xmp"].contains($0.pathExtension) })

        let firstEvents = first.libraryWorkflowTrackingState?.exportTracking.successfulEvents ?? []
        let secondEvents = second.libraryWorkflowTrackingState?.exportTracking.successfulEvents ?? []
        XCTAssertEqual(firstEvents.count, 1)
        XCTAssertEqual(secondEvents.count, 1)
        let firstEvent = try XCTUnwrap(firstEvents.first)
        let secondEvent = try XCTUnwrap(secondEvents.first)
        XCTAssertNotEqual(firstEvent.id, secondEvent.id)
        XCTAssertEqual(firstEvent.artifactPaths, imageFiles.map { $0.standardizedFileURL.path })
        XCTAssertEqual(secondEvent.artifactPaths, firstEvent.artifactPaths)
        XCTAssertEqual(firstEvent.sourceIdentity, try RenderManifest.sourceIdentity(for: first.rawScanURL))
        XCTAssertEqual(secondEvent.sourceIdentity, try RenderManifest.sourceIdentity(for: second.rawScanURL))
        XCTAssertFalse(ExportArtifactCommitJournal.journalExists(transactionID: firstEvent.id))
        XCTAssertFalse(ExportArtifactCommitJournal.journalExists(transactionID: secondEvent.id))

        let catalog = try XCTUnwrap(LibraryCatalogFile.loadPrimary(from: model.libraryCatalogURL))
        let eventIDs = catalog.frames.flatMap(\.exportTracking.successfulEvents).map(\.id)
        XCTAssertEqual(Set(eventIDs).count, 2)
        XCTAssertFalse(model.isAcknowledgedLibraryTransactionActive)
        XCTAssertFalse(model.librarySaveRequestedDuringTransaction)
    }

    func testCatalogCommitFailureRollsBackPublishedPagesAndTracking() async throws {
        let exportRoot = root.appendingPathComponent("Exports", isDirectory: true)
        let diskStore = DiskStorageStore(defaults: defaults)
        diskStore.exportPath = exportRoot.path
        let printStore = PrintWorkspaceSettingsStore(defaults: defaults)
        printStore.layoutMode = .contactSheet
        printStore.paperSize = .fourBySix
        printStore.orientation = .landscape
        printStore.packageSettings = PrintPackageSettings(
            mode: .contactSheet,
            contactRows: 1,
            contactColumns: 1
        )
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            printWorkspaceSettingsStore: printStore,
            diskStorageStore: diskStore,
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )
        try setSyntheticPrinterOutputProfile(on: model)
        await model.restoreLibraryOnLaunch()
        let frame = try makeFrame(index: 1, width: 24, height: 16)
        model.frames = [frame]
        frame.hasDevelopedOnce = true
        frame.displayPixelSize = CGSize(width: 24, height: 16)
        model.updateInteractionScope([frame.id])
        model.selectedFrameIDs = [frame.id]
        model.exportFormat = .png
        model.exportDPI = 72
        let previousTracking = frame.libraryWorkflowTrackingState
        let previousJournalFiles = Set(regularFiles(
            below: ExportArtifactCommitJournal.defaultDirectoryURL()
        ).map(\.standardizedFileURL.path))

        model.exportPrintSelectionToFolder(
            settings: printStore.compositionSettings(dpi: 72)
        )
        try await waitForPackageExport(model)

        XCTAssertTrue(regularFiles(below: exportRoot).isEmpty)
        XCTAssertEqual(frame.libraryWorkflowTrackingState, previousTracking)
        let currentJournalFiles = Set(regularFiles(
            below: ExportArtifactCommitJournal.defaultDirectoryURL()
        ).map(\.standardizedFileURL.path))
        XCTAssertEqual(currentJournalFiles, previousJournalFiles)
    }

    func testRollbackFailedPackageCatalogCommitKeepsEventsAndBlocksLibrary() async throws {
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            printWorkspaceSettingsStore: PrintWorkspaceSettingsStore(defaults: defaults),
            diskStorageStore: DiskStorageStore(defaults: defaults),
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )
        await model.restoreLibraryOnLaunch()
        let frame = try makeFrame(index: 1, width: 24, height: 16)
        model.frames = [frame]
        XCTAssertTrue(model.assignNewPersistentFrames([frame]))
        let trackingIdentity = try XCTUnwrap(
            ExportFrameTrackingIdentity.capture(frame: frame, format: .png)
        )
        let sourceIdentity = try RenderManifest.sourceIdentity(for: frame.rawScanURL)
        let sourceGeneration = ExportFrameSourceGeneration(
            rawScanURL: frame.rawScanURL,
            sourceIdentity: sourceIdentity
        )
        let sourceVerification = ExportFrameSourceVerification(
            sourceIdentity: sourceIdentity,
            fileIdentity: try XCTUnwrap(
                ExportArtifactFileIdentityInspector.sourceFile(at: frame.rawScanURL)
            )
        )
        let outputURL = root.appendingPathComponent("package-output.png")
        let event = LibraryExportEvent(
            id: UUID(),
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            primaryOutputPath: outputURL.path,
            artifactPaths: [outputURL.path],
            formatRawValue: ExportFormat.png.rawValue,
            renderKind: .developed,
            developRecipeSHA256: trackingIdentity.developRecipeSHA256,
            defectRecipeSHA256: trackingIdentity.defectRecipeIdentity?.recipeSHA256,
            sourceIdentity: sourceIdentity
        )

        let outcome = model.commitSuccessfulPrintPackageEvents(
            [PrintPackageContributorCommit(
                frame: frame,
                trackingIdentity: trackingIdentity,
                sourceGeneration: sourceGeneration,
                event: event
            )],
            format: .png,
            sourceVerifications: [frame.id: sourceVerification],
            catalogCommit: { .failure(.rollbackFailed) }
        )

        XCTAssertEqual(outcome, .indeterminate)
        XCTAssertEqual(
            frame.libraryWorkflowTrackingState?.exportTracking.successfulEvents,
            [event]
        )
        XCTAssertEqual(model.libraryCatalogBlockReason, .writeFailed)
        XCTAssertEqual(model.libraryLifecycleState, .blocked)
        XCTAssertFalse(model.libraryPersistenceEnabled)
        XCTAssertFalse(model.isAcknowledgedLibraryTransactionActive)
    }

    func testLegacyPrintTargetStillRequiresPrinterOutputProfile() throws {
        let exportRoot = root.appendingPathComponent("Exports", isDirectory: true)
        let diskStore = DiskStorageStore(defaults: defaults)
        diskStore.exportPath = exportRoot.path
        let printStore = PrintWorkspaceSettingsStore(defaults: defaults)
        printStore.layoutMode = .contactSheet
        printStore.packageSettings = PrintPackageSettings(
            mode: .contactSheet,
            contactRows: 1,
            contactColumns: 2
        )
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            printWorkspaceSettingsStore: printStore,
            diskStorageStore: diskStore,
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )
        let softProofProfile = try ICCOutputProfileTestFixture.snapshot()
        XCTAssertTrue(model.setSoftProofICCProfile(
            data: softProofProfile.iccProfileData,
            name: softProofProfile.profileName
        ))
        model.softProofEnabled = true
        XCTAssertNil(model.selectedPrinterOutputProfile)

        let frame = try makeFrame(index: 1, width: 24, height: 16)
        frame.updateParams { $0.developTarget = .print }
        model.frames = [frame]
        frame.hasDevelopedOnce = true
        frame.displayPixelSize = CGSize(width: 24, height: 16)
        model.updateInteractionScope([frame.id])
        model.selectedFrameIDs = [frame.id]
        model.exportFormat = .png

        model.exportPrintSelectionToFolder(
            settings: printStore.compositionSettings(dpi: 72)
        )

        XCTAssertFalse(model.isPrintPackageExporting)
        XCTAssertFalse(frame.isDeveloping)
        XCTAssertEqual(model.statusMessage, model.text(.printOutputProfileRequired))
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportRoot.path))
    }

    func testCPrintProfileIsAppliedToCompositeExport() async throws {
        let exportRoot = root.appendingPathComponent("Exports", isDirectory: true)
        let diskStore = DiskStorageStore(defaults: defaults)
        diskStore.exportPath = exportRoot.path
        let printStore = PrintWorkspaceSettingsStore(defaults: defaults)
        printStore.outputProcess = .cPrint
        printStore.layoutMode = .contactSheet
        printStore.paperSize = .fourBySix
        printStore.orientation = .landscape
        printStore.packageSettings = PrintPackageSettings(
            mode: .contactSheet,
            contactRows: 1,
            contactColumns: 2
        )
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            printWorkspaceSettingsStore: printStore,
            diskStorageStore: diskStore,
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )
        let profile = try ICCOutputProfileTestFixture.snapshot()
        XCTAssertTrue(model.setCPrintProofICCProfile(
            data: profile.iccProfileData,
            name: profile.profileName
        ))
        await model.restoreLibraryOnLaunch()
        let first = try makeFrame(index: 1, width: 24, height: 16)
        let second = try makeFrame(index: 2, width: 16, height: 24)
        model.frames = [first, second]
        XCTAssertTrue(model.assignNewPersistentFrames([first, second]))
        first.hasDevelopedOnce = true
        second.hasDevelopedOnce = true
        first.displayPixelSize = CGSize(width: 24, height: 16)
        second.displayPixelSize = CGSize(width: 16, height: 24)
        model.updateInteractionScope([first.id, second.id])
        model.selectedFrameIDs = [first.id, second.id]
        model.exportFormat = .png
        model.exportDPI = 72
        XCTAssertTrue(model.saveLibrary(synchronous: true))

        model.exportPrintSelectionToFolder(
            settings: printStore.compositionSettings(dpi: 72)
        )
        XCTAssertTrue(model.isPrintPackageExporting, model.statusMessage)
        try await waitForPackageExport(model)

        let outputs = regularFiles(below: exportRoot).filter { $0.pathExtension == "png" }
        let output = try XCTUnwrap(outputs.first)
        XCTAssertEqual(outputs.count, 1)
        XCTAssertEqual(
            ICCOutputProfileSnapshot.embeddedProfileSHA256(at: output),
            profile.profileSHA256
        )
        let firstEvent = try XCTUnwrap(
            first.libraryWorkflowTrackingState?.exportTracking.successfulEvents.first
        )
        let secondEvent = try XCTUnwrap(
            second.libraryWorkflowTrackingState?.exportTracking.successfulEvents.first
        )
        XCTAssertEqual(firstEvent.artifactPaths, [output.standardizedFileURL.path])
        XCTAssertEqual(secondEvent.artifactPaths, firstEvent.artifactPaths)
    }

    func testPageLimitFailureIsReportedBeforeRenderingStarts() throws {
        let printStore = PrintWorkspaceSettingsStore(defaults: defaults)
        printStore.layoutMode = .picturePackage
        printStore.packageSettings = PrintPackageSettings(mode: .picturePackage)
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            printWorkspaceSettingsStore: printStore,
            diskStorageStore: DiskStorageStore(defaults: defaults),
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )
        try setSyntheticPrinterOutputProfile(on: model)
        let frames = (0...(PrintPackageSettings.maximumPageCount * 3)).map { index in
            let frame = ScanFrame(
                scanIndex: index + 1,
                rawScanURL: root.appendingPathComponent("unread-source-\(index).tiff"),
                filmType: .colorPositive,
                sourcePixelWidth: 24,
                sourcePixelHeight: 16
            )
            frame.hasDevelopedOnce = true
            return frame
        }
        model.frames = frames
        model.updateInteractionScope(frames.map(\.id))
        model.selectedFrameIDs = Set(frames.map(\.id))
        model.exportFormat = .png

        model.exportPrintSelectionToFolder(
            settings: printStore.compositionSettings(dpi: 72)
        )

        XCTAssertFalse(model.isPrintPackageExporting)
        XCTAssertEqual(model.statusMessage, model.text(.printPackagePageLimit))
    }

    /// 인화 빠른 내보내기 — 프린터 ICC 없이 배포 색공간만으로 페이지를 쓴다.
    func testQuickPrintPackageExportWritesPagesWithoutPrinterProfile() async throws {
        let quickRoot = root.appendingPathComponent("QuickExports", isDirectory: true)
        let diskStore = DiskStorageStore(defaults: defaults)
        diskStore.quickExportPath = quickRoot.path
        let printStore = PrintWorkspaceSettingsStore(defaults: defaults)
        printStore.layoutMode = .contactSheet
        printStore.paperSize = .fourBySix
        printStore.orientation = .landscape
        printStore.marginMM = 5
        printStore.packageSettings = PrintPackageSettings(
            mode: .contactSheet,
            contactRows: 1,
            contactColumns: 2,
            horizontalSpacingMM: 2,
            verticalSpacingMM: 0
        )
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            printWorkspaceSettingsStore: printStore,
            diskStorageStore: diskStore,
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )
        await model.restoreLibraryOnLaunch()
        let first = try makeFrame(index: 11, width: 24, height: 16)
        let second = try makeFrame(index: 12, width: 16, height: 24)
        model.frames = [first, second]
        XCTAssertTrue(model.assignNewPersistentFrames([first, second]))
        first.hasDevelopedOnce = true
        second.hasDevelopedOnce = true
        first.displayPixelSize = CGSize(width: 24, height: 16)
        second.displayPixelSize = CGSize(width: 16, height: 24)
        model.updateInteractionScope([first.id, second.id])
        model.selectedFrameIDs = [first.id, second.id]
        model.quickExportFormat = .jpeg
        model.quickExportDPI = 72

        model.quickExportPrintSelection(settings: printStore.compositionSettings(dpi: 72))
        try await waitForPackageExport(model)

        let imageFiles = regularFiles(below: quickRoot).filter { $0.pathExtension == "jpg" }
        XCTAssertEqual(imageFiles.count, 1, "status=\(model.statusMessage)")
    }

    /// 여러 장을 고른 인화 시트는 **용지 한 장**만 나온다. 원본은 셀이 요구하는 해상도까지만
    /// 현상하므로, 장수가 늘어도 풀해상도 현상이 장수만큼 늘지 않는다.
    func testContactSheetExportWritesOneSheetForEverySelectedPhoto() async throws {
        let exportRoot = root.appendingPathComponent("SheetExports", isDirectory: true)
        let diskStore = DiskStorageStore(defaults: defaults)
        diskStore.exportPath = exportRoot.path
        let printStore = PrintWorkspaceSettingsStore(defaults: defaults)
        printStore.layoutMode = .contactSheet
        printStore.paperSize = .a4
        printStore.orientation = .landscape
        printStore.marginMM = 5
        printStore.packageSettings = PrintPackageSettings(
            mode: .contactSheet,
            contactRows: 6,
            contactColumns: 7,
            horizontalSpacingMM: 2,
            verticalSpacingMM: 2
        )
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            printWorkspaceSettingsStore: printStore,
            diskStorageStore: diskStore,
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )
        await model.restoreLibraryOnLaunch()
        let frames = try (0..<39).map { index -> ScanFrame in
            let frame = try makeFrame(index: 30 + index, width: 240, height: 160)
            frame.displayPixelSize = CGSize(width: 240, height: 160)
            return frame
        }
        model.frames = frames
        XCTAssertTrue(model.assignNewPersistentFrames(frames))
        model.updateInteractionScope(frames.map(\.id))
        model.selectedFrameIDs = Set(frames.map(\.id))
        model.exportFormat = .png
        model.exportDPI = 72

        XCTAssertFalse(model.canExportSelection)
        XCTAssertTrue(model.canExportPrintSelection)
        model.exportPrintSelectionToFolder(settings: model.printCompositionSettings(dpi: 72))
        try await waitForPackageExport(model)

        let imageFiles = regularFiles(below: exportRoot).filter { $0.pathExtension == "png" }
        XCTAssertEqual(imageFiles.count, 1, "status=\(model.statusMessage)")
        let outputPath = try XCTUnwrap(imageFiles.first).standardizedFileURL.path
        XCTAssertTrue(frames.allSatisfy {
            $0.libraryWorkflowTrackingState?.exportTracking.successfulEvents
                .first?.artifactPaths == [outputPath]
        })
    }

    /// 단일 이미지 레이아웃은 한 롤 39장을 각각 한 장의 인화 파일로 배치 처리한다.
    func testSingleImageQuickExportWritesThirtyNinePrints() async throws {
        let quickRoot = root.appendingPathComponent("SingleQuickExports", isDirectory: true)
        let diskStore = DiskStorageStore(defaults: defaults)
        diskStore.quickExportPath = quickRoot.path
        let printStore = PrintWorkspaceSettingsStore(defaults: defaults)
        printStore.layoutMode = .singleImage
        printStore.paperSize = .fourBySix
        printStore.orientation = .landscape
        printStore.marginMM = 5
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            printWorkspaceSettingsStore: printStore,
            diskStorageStore: diskStore,
            libraryCatalogURL: root.appendingPathComponent("single-library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("single-defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("SingleBackups")
        )
        await model.restoreLibraryOnLaunch()
        let frames = try (0..<39).map { index -> ScanFrame in
            let frame = try makeFrame(index: 100 + index, width: 240, height: 160)
            frame.displayPixelSize = CGSize(width: 240, height: 160)
            return frame
        }
        model.frames = frames
        XCTAssertTrue(model.assignNewPersistentFrames(frames))
        model.updateInteractionScope(frames.map(\.id))
        model.selectedFrameIDs = Set(frames.map(\.id))
        model.quickExportFormat = .jpeg
        model.quickExportDPI = 72

        XCTAssertFalse(model.canQuickExportSelection)
        XCTAssertTrue(model.canQuickExportPrintSelection)
        model.quickExportPrintSelection(settings: printStore.compositionSettings(dpi: 72))
        try await waitForBatchExport(model)

        let imageFiles = regularFiles(below: quickRoot).filter { $0.pathExtension == "jpg" }
        XCTAssertEqual(model.exportBatchStore.items.count, 39)
        XCTAssertEqual(model.exportBatchStore.completedCount, 39, "status=\(model.statusMessage)")
        XCTAssertEqual(model.exportBatchStore.failedCount, 0, "status=\(model.statusMessage)")
        XCTAssertEqual(imageFiles.count, 39, "status=\(model.statusMessage)")
    }

    func testPicturePackageQuickExportWritesTenPagesForThirtyNinePhotos() async throws {
        let quickRoot = root.appendingPathComponent("PictureQuickExports", isDirectory: true)
        let diskStore = DiskStorageStore(defaults: defaults)
        diskStore.quickExportPath = quickRoot.path
        let printStore = PrintWorkspaceSettingsStore(defaults: defaults)
        printStore.layoutMode = .picturePackage
        printStore.paperSize = .fourBySix
        printStore.orientation = .landscape
        printStore.marginMM = 5
        printStore.packageSettings = PrintPackageSettings(
            mode: .picturePackage,
            pictureTemplate: .fourUp
        )
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            printWorkspaceSettingsStore: printStore,
            diskStorageStore: diskStore,
            libraryCatalogURL: root.appendingPathComponent("picture-library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("picture-defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("PictureBackups")
        )
        await model.restoreLibraryOnLaunch()
        let frames = try makeDevelopedFrames(range: 200..<239)
        model.frames = frames
        XCTAssertTrue(model.assignNewPersistentFrames(frames))
        model.updateInteractionScope(frames.map(\.id))
        model.selectedFrameIDs = Set(frames.map(\.id))
        model.quickExportFormat = .jpeg
        model.quickExportDPI = 72
        frames.forEach { frame in
            frame.printPackagePreviewTask = Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }

        model.quickExportPrintSelection(settings: printStore.compositionSettings(dpi: 72))
        XCTAssertTrue(frames.allSatisfy { $0.printPackagePreviewTask == nil })
        try await waitForPackageExport(model)

        let imageFiles = regularFiles(below: quickRoot).filter { $0.pathExtension == "jpg" }
        XCTAssertEqual(imageFiles.count, 10, "status=\(model.statusMessage)")
        XCTAssertTrue(frames.allSatisfy {
            $0.libraryWorkflowTrackingState?.exportTracking.successfulEvents.count == 1
        })
    }

    func testCustomPackageQuickExportWritesOnePageForThirtyNinePhotos() async throws {
        let quickRoot = root.appendingPathComponent("CustomQuickExports", isDirectory: true)
        let diskStore = DiskStorageStore(defaults: defaults)
        diskStore.quickExportPath = quickRoot.path
        let printStore = PrintWorkspaceSettingsStore(defaults: defaults)
        printStore.layoutMode = .customPackage
        printStore.paperSize = .a4
        printStore.orientation = .landscape
        printStore.marginMM = 5
        printStore.packageSettings = PrintPackageSettings(mode: .customPackage)
        printStore.prepareDefaultCustomPackage(sourceCount: 39)
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            printWorkspaceSettingsStore: printStore,
            diskStorageStore: diskStore,
            libraryCatalogURL: root.appendingPathComponent("custom-library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("custom-defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("CustomBackups")
        )
        await model.restoreLibraryOnLaunch()
        let frames = try makeDevelopedFrames(range: 300..<339)
        model.frames = frames
        XCTAssertTrue(model.assignNewPersistentFrames(frames))
        model.updateInteractionScope(frames.map(\.id))
        model.selectedFrameIDs = Set(frames.map(\.id))
        model.quickExportFormat = .jpeg
        model.quickExportDPI = 72

        model.quickExportPrintSelection(settings: printStore.compositionSettings(dpi: 72))
        try await waitForPackageExport(model)

        let imageFiles = regularFiles(below: quickRoot).filter { $0.pathExtension == "jpg" }
        XCTAssertEqual(imageFiles.count, 1, "status=\(model.statusMessage)")
        let outputPath = try XCTUnwrap(imageFiles.first).standardizedFileURL.path
        XCTAssertTrue(frames.allSatisfy {
            $0.libraryWorkflowTrackingState?.exportTracking.successfulEvents
                .first?.artifactPaths == [outputPath]
        })
    }

    private func setSyntheticPrinterOutputProfile(on model: AppModel) throws {
        let profile = try ICCOutputProfileTestFixture.snapshot()
        XCTAssertTrue(model.setPrinterOutputICCProfile(
            data: profile.iccProfileData,
            name: profile.profileName
        ))
        XCTAssertEqual(model.selectedPrinterOutputProfile, profile)
    }

    private func makeFrame(index: Int, width: Int, height: Int) throws -> ScanFrame {
        let url = root.appendingPathComponent("source-\(index).tiff")
        try MockScannerBackend.writeSyntheticNegative(width: width, height: height, to: url)
        let frame = ScanFrame(
            scanIndex: index,
            rawScanURL: url,
            filmType: .colorPositive,
            sourcePixelWidth: width,
            sourcePixelHeight: height
        )
        _ = LibraryFrameRecord(frame: frame)
        return frame
    }

    private func makeDevelopedFrames(range: Range<Int>) throws -> [ScanFrame] {
        try range.map { index in
            let frame = try makeFrame(index: index, width: 240, height: 160)
            frame.hasDevelopedOnce = true
            frame.displayPixelSize = CGSize(width: 240, height: 160)
            return frame
        }
    }

    private func waitForPackageExport(_ model: AppModel) async throws {
        for _ in 0..<500 {
            if !model.isPrintPackageExporting { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("print package export did not finish")
    }

    private func waitForBatchExport(_ model: AppModel) async throws {
        for _ in 0..<2_000 {
            if !model.exportBatchStore.isRunning { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("single-image print export did not finish")
    }

    private func regularFiles(below directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            return url
        }.sorted { $0.path < $1.path }
    }
}
