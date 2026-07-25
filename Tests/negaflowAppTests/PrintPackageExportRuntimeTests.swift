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
        try await waitForPackageExport(model)

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

    func testMissingPrinterOutputProfileFailsBeforeRenderingOrWriting() throws {
        let exportRoot = root.appendingPathComponent("Exports", isDirectory: true)
        let diskStore = DiskStorageStore(defaults: defaults)
        diskStore.exportPath = exportRoot.path
        let printStore = PrintWorkspaceSettingsStore(defaults: defaults)
        printStore.layoutMode = .contactSheet
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
        let softProofProfile = try ICCOutputProfileTestFixture.snapshot()
        XCTAssertTrue(model.setSoftProofICCProfile(
            data: softProofProfile.iccProfileData,
            name: softProofProfile.profileName
        ))
        model.softProofEnabled = true
        XCTAssertNil(model.selectedPrinterOutputProfile)

        let frame = try makeFrame(index: 1, width: 24, height: 16)
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
        let frames = (0...PrintPackageSettings.maximumPageCount).map { index in
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

    private func waitForPackageExport(_ model: AppModel) async throws {
        for _ in 0..<500 {
            if !model.isPrintPackageExporting { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("print package export did not finish")
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
