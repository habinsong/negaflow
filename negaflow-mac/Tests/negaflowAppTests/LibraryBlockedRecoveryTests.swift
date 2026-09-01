import XCTest
@testable import negaflowApp

@MainActor
final class LibraryBlockedRecoveryTests: XCTestCase {
    func testRetryReusesHeldProcessLockAndOpensRepairedCatalog() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try Data("not-json".utf8).write(to: paths.catalog, options: .atomic)
        let model = makeModel(paths)

        await model.restoreLibraryOnLaunch()
        XCTAssertEqual(model.libraryLifecycleState, .blocked)
        XCTAssertEqual(model.libraryCatalogBlockReason, .corrupt)
        XCTAssertNotNil(model.libraryProcessLock)
        XCTAssertFalse(model.allowsLibraryMutation)

        let valid = try XCTUnwrap(LibraryCatalogFile.encode(LibraryCatalog()))
        try valid.write(to: paths.catalog, options: .atomic)

        let recovered = await model.retryBlockedLibraryOpen()
        XCTAssertTrue(recovered)
        XCTAssertEqual(model.libraryLifecycleState, .ready)
        XCTAssertNil(model.libraryCatalogBlockReason)
        XCTAssertTrue(model.libraryPersistenceEnabled)
        XCTAssertNotNil(model.libraryProcessLock)
        XCTAssertTrue(model.allowsLibraryMutation)
    }

    func testFailedRetryKeepsMutationBlockedAndCatalogUnchanged() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let corrupt = Data("still-not-json".utf8)
        try corrupt.write(to: paths.catalog, options: .atomic)
        let model = makeModel(paths)

        await model.restoreLibraryOnLaunch()
        let recovered = await model.retryBlockedLibraryOpen()
        XCTAssertFalse(recovered)

        XCTAssertEqual(model.libraryLifecycleState, .blocked)
        XCTAssertEqual(model.libraryCatalogBlockReason, .corrupt)
        XCTAssertFalse(model.libraryPersistenceEnabled)
        XCTAssertFalse(model.allowsLibraryMutation)
        XCTAssertEqual(try Data(contentsOf: paths.catalog), corrupt)
    }

    func testRecoveryDiagnosticsAreStableAndContainNoFrameSourcePaths() {
        let generation = LibraryBackupGeneration(
            id: "backup-42",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            frameCount: 12,
            defectRecipeCount: 3,
            catalogVersion: LibraryCatalog.currentVersion,
            state: .checksummed
        )
        let diagnostics = LibraryRecoveryDiagnostics(
            appVersion: "1.2.3",
            failureCode: "corrupt",
            lifecycleCode: "blocked",
            catalogPath: "~/Library/Application Support/negaflow/library.json",
            backupDirectoryPath: "~/Library/Application Support/negaflow/Backups",
            pendingRestoreID: nil,
            generations: [generation]
        ).text

        XCTAssertTrue(diagnostics.hasPrefix("negaflow.library-recovery.v2\n"))
        XCTAssertTrue(diagnostics.contains("failure=corrupt"))
        XCTAssertTrue(diagnostics.contains("backup[0].state=checksummed"))
        XCTAssertTrue(diagnostics.contains("backup[0].frames=12"))
        XCTAssertFalse(diagnostics.contains("rawScanPath"))
        XCTAssertFalse(diagnostics.contains("/Users/"))
    }

    func testStartingFreshEscapesABlockedLibraryAndKeepsTheOldCatalog() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let corrupt = Data("not-json-and-no-backups".utf8)
        try corrupt.write(to: paths.catalog, options: .atomic)
        let model = makeModel(paths)

        await model.restoreLibraryOnLaunch()
        XCTAssertEqual(model.libraryLifecycleState, .blocked)
        // 백업이 하나도 없어서 복원으로는 빠져나올 수 없는 상태다.
        let generations = try await model.libraryBackupGenerations()
        XCTAssertTrue(generations.isEmpty)

        let started = await model.startFreshLibraryFromRecovery()

        XCTAssertTrue(started)
        XCTAssertEqual(model.libraryLifecycleState, .ready)
        XCTAssertNil(model.libraryCatalogBlockReason)
        XCTAssertTrue(model.libraryPersistenceEnabled)
        XCTAssertTrue(model.allowsLibraryMutation)

        // 열지 못한 카탈로그는 지우지 않고 옆에 보관한다.
        let preserved = try FileManager.default
            .contentsOfDirectory(atPath: paths.root.path)
            .filter { $0.hasPrefix("library.corrupt-") }
        XCTAssertEqual(preserved.count, 1)
        let preservedURL = paths.root.appendingPathComponent(try XCTUnwrap(preserved.first))
        XCTAssertEqual(try Data(contentsOf: preservedURL), corrupt)
    }

    func testRecoveryActionsAreLocalizedInEverySupportedLanguage() {
        let languages: [AppLanguage] = [
            .english, .korean, .japanese, .simplifiedChinese, .french, .german,
        ]
        // allCases 로 도는 이유: 키를 새로 만들고 번역을 빼먹으면 여기서 걸려야 한다.
        let keys = LibraryRecoveryLocalizedText.allCases
        for language in languages {
            for key in keys {
                XCTAssertFalse(
                    AppLocalization.libraryRecoveryText(key, language: language).isEmpty,
                    "\(language.rawValue) \(key)"
                )
            }
        }
    }

    func testAmbiguousExportRecoveryActionsAreLocalizedInEverySupportedLanguage() {
        let languages: [AppLanguage] = [
            .english, .korean, .japanese, .simplifiedChinese, .french, .german,
        ]
        let keys: [AppLocalizedText] = [
            .libraryAmbiguousExportRecoveryTitle,
            .libraryAmbiguousExportRecoveryMessage,
            .libraryAmbiguousExportTransaction,
            .libraryAmbiguousExportKeepFiles,
            .libraryAmbiguousExportDeleteFiles,
            .libraryAmbiguousExportDeleteConfirmationTitle,
            .libraryAmbiguousExportDeleteConfirmationMessage,
            .libraryAmbiguousExportRecoveryFailed,
        ]
        for language in languages {
            for key in keys {
                XCTAssertFalse(
                    AppLocalization.text(key, language: language).isEmpty,
                    "\(language.rawValue) \(key)"
                )
            }
        }
    }

    func testAmbiguousExportTransactionsArePreservedSortedWithoutDuplicates() {
        let model = AppModel()
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        var report = ExportArtifactCommitReconciliationReport()
        report.ambiguousTransactionIDs = [second, first, second]

        model.preserveAmbiguousExportCommitTransactions(from: report)
        model.preserveAmbiguousExportCommitTransactions(from: report)

        XCTAssertEqual(model.ambiguousExportCommitTransactionIDs, [first, second])
        XCTAssertEqual(model.preservableExportCommitTransactionIDs, [first, second])
    }

    func testPreservingAmbiguousExportKeepsArtifactAndRetriesLibraryOpen() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let fixture = try makeAmbiguousExportFixture(in: paths.root)
        let model = makeModel(paths)
        try writeEmptyCatalog(to: paths.catalog)
        await model.restoreLibraryOnLaunch()
        XCTAssertEqual(model.libraryLifecycleState, .ready)
        model.blockLibraryAfterIndeterminateExportState()
        model.preserveAmbiguousExportCommitTransactions(from: fixture.report)

        let resolved = await model.resolveAmbiguousExportCommitPreservingArtifacts(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )

        XCTAssertTrue(resolved)
        XCTAssertEqual(model.libraryLifecycleState, .ready)
        XCTAssertTrue(model.ambiguousExportCommitTransactionIDs.isEmpty)
        XCTAssertTrue(model.preservableExportCommitTransactionIDs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.finalURL.path))
        XCTAssertFalse(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testCommittedMismatchOffersKeepOnlyAndCanUnblockLibrary() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let fixture = try makeAmbiguousExportFixture(in: paths.root)
        try ExportArtifactCommitJournal.markCatalogCommitted(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        let replacement = Data("current user export".utf8)
        try replacement.write(to: fixture.finalURL, options: .atomic)
        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: fixture.journalDirectory
        )
        XCTAssertTrue(report.ambiguousTransactionIDs.isEmpty)
        XCTAssertEqual(report.preservableTransactionIDs, [fixture.transactionID])

        let model = makeModel(paths)
        try writeEmptyCatalog(to: paths.catalog)
        await model.restoreLibraryOnLaunch()
        model.blockLibraryAfterIndeterminateExportState()
        model.preserveAmbiguousExportCommitTransactions(from: report)

        let deleted = await model.resolveAmbiguousExportCommitDeletingOwnedArtifacts(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        XCTAssertFalse(deleted)
        let preserved = await model.resolveAmbiguousExportCommitPreservingArtifacts(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        XCTAssertTrue(preserved)
        XCTAssertEqual(model.libraryLifecycleState, .ready)
        XCTAssertEqual(try Data(contentsOf: fixture.finalURL), replacement)
        XCTAssertFalse(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testStartupPublishesKeepOnlyRecoveryForCommittedArtifactMismatch() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let fixture = try makeAmbiguousExportFixture(in: paths.root)
        try ExportArtifactCommitJournal.markCatalogCommitted(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        let replacement = Data("current committed-path file".utf8)
        try replacement.write(to: fixture.finalURL, options: .atomic)
        let model = makeModel(paths)
        try writeEmptyCatalog(to: paths.catalog)

        await model.restoreLibraryOnLaunch(
            reusingHeldProcessLock: false,
            exportJournalDirectory: fixture.journalDirectory
        )

        XCTAssertEqual(model.libraryLifecycleState, .blocked)
        XCTAssertTrue(model.ambiguousExportCommitTransactionIDs.isEmpty)
        XCTAssertEqual(
            model.preservableExportCommitTransactionIDs,
            [fixture.transactionID]
        )
        XCTAssertEqual(try Data(contentsOf: fixture.finalURL), replacement)
    }

    func testMultipleAmbiguousExportsResolveOneAtATimeBeforeLibraryOpens() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let first = try makeAmbiguousExportFixture(in: paths.root, label: "first")
        let second = try makeAmbiguousExportFixture(in: paths.root, label: "second")
        XCTAssertEqual(
            Set(second.report.ambiguousTransactionIDs),
            Set([first.transactionID, second.transactionID])
        )
        let model = makeModel(paths)
        try writeEmptyCatalog(to: paths.catalog)
        await model.restoreLibraryOnLaunch()
        model.blockLibraryAfterIndeterminateExportState()
        model.preserveAmbiguousExportCommitTransactions(from: second.report)

        let firstResolved = await model.resolveAmbiguousExportCommitPreservingArtifacts(
            transactionID: first.transactionID,
            in: first.journalDirectory
        )
        XCTAssertTrue(firstResolved)
        XCTAssertEqual(model.libraryLifecycleState, .blocked)
        XCTAssertEqual(model.ambiguousExportCommitTransactionIDs, [second.transactionID])

        let secondResolved = await model.resolveAmbiguousExportCommitPreservingArtifacts(
            transactionID: second.transactionID,
            in: second.journalDirectory
        )
        XCTAssertTrue(secondResolved)
        XCTAssertEqual(model.libraryLifecycleState, .ready)
        XCTAssertTrue(model.ambiguousExportCommitTransactionIDs.isEmpty)
        XCTAssertTrue(model.preservableExportCommitTransactionIDs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.finalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.finalURL.path))
    }

    func testStartupBlocksAndPublishesAmbiguousExportRecoveryWithoutDeletingArtifact() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let fixture = try makeAmbiguousExportFixture(in: paths.root)
        let model = makeModel(paths)
        try writeEmptyCatalog(to: paths.catalog)

        await model.restoreLibraryOnLaunch(
            reusingHeldProcessLock: false,
            exportJournalDirectory: fixture.journalDirectory
        )

        XCTAssertEqual(model.libraryLifecycleState, .blocked)
        XCTAssertEqual(model.libraryCatalogBlockReason, .writeFailed)
        XCTAssertFalse(model.allowsLibraryMutation)
        XCTAssertEqual(
            model.ambiguousExportCommitTransactionIDs,
            [fixture.transactionID]
        )
        XCTAssertEqual(
            model.preservableExportCommitTransactionIDs,
            [fixture.transactionID]
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.finalURL.path))
        XCTAssertTrue(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testFailedCatalogRetryRevokesStaleAmbiguousExportDeletion() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let fixture = try makeAmbiguousExportFixture(in: paths.root)
        let originalFinalData = try Data(contentsOf: fixture.finalURL)
        let model = makeModel(paths)
        try writeEmptyCatalog(to: paths.catalog)

        await model.restoreLibraryOnLaunch(
            reusingHeldProcessLock: false,
            exportJournalDirectory: fixture.journalDirectory
        )
        XCTAssertEqual(model.libraryLifecycleState, .blocked)
        XCTAssertEqual(
            model.ambiguousExportCommitTransactionIDs,
            [fixture.transactionID]
        )

        try Data("not-json".utf8).write(to: paths.catalog, options: .atomic)
        let recovered = await model.retryBlockedLibraryOpen(
            exportJournalDirectory: fixture.journalDirectory
        )
        let deleted = await model.resolveAmbiguousExportCommitDeletingOwnedArtifacts(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )

        XCTAssertFalse(recovered)
        XCTAssertEqual(model.libraryLifecycleState, .blocked)
        XCTAssertEqual(model.libraryCatalogBlockReason, .corrupt)
        XCTAssertTrue(model.ambiguousExportCommitTransactionIDs.isEmpty)
        XCTAssertFalse(deleted)
        XCTAssertEqual(try Data(contentsOf: fixture.finalURL), originalFinalData)
        XCTAssertTrue(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testRuntimeRecoveryReplacesPersistentFramesWithoutDuplicateUUIDs() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let model = makeModel(paths)
        await model.restoreLibraryOnLaunch()
        let sourceURL = paths.root.appendingPathComponent("source.tiff")
        try Data("source".utf8).write(to: sourceURL)
        let original = ScanFrame(
            scanIndex: 1,
            rawScanURL: sourceURL,
            filmType: .colorNegative,
            sourcePixelWidth: 16,
            sourcePixelHeight: 12
        )
        model.frames = [original]
        XCTAssertTrue(model.assignNewPersistentFrames([original]))
        XCTAssertTrue(model.saveLibrary(synchronous: true))
        let persistedTracking = original.libraryWorkflowTrackingState
        model.blockLibraryAfterIndeterminateExportState()
        var inMemoryTracking = try XCTUnwrap(original.libraryWorkflowTrackingState)
        inMemoryTracking.exportTracking.successfulEvents.append(LibraryExportEvent(
            id: UUID(),
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            primaryOutputPath: paths.root.appendingPathComponent("uncertain.jpg").path,
            artifactPaths: [paths.root.appendingPathComponent("uncertain.jpg").path],
            formatRawValue: "jpeg",
            renderKind: .developed,
            developRecipeSHA256: inMemoryTracking.userEditTracking.currentRecipeSHA256,
            defectRecipeSHA256: nil
        ))
        original.libraryWorkflowTrackingState = inMemoryTracking

        let recovered = await model.retryBlockedLibraryOpen()
        XCTAssertTrue(recovered)

        XCTAssertEqual(model.frames.count, 1)
        XCTAssertEqual(Set(model.frames.map(\.id)), Set([original.id]))
        XCTAssertFalse(model.frames[0] === original)
        XCTAssertEqual(
            model.frames[0].libraryWorkflowTrackingState,
            persistedTracking
        )
        XCTAssertNotEqual(
            model.frames[0].libraryWorkflowTrackingState,
            original.libraryWorkflowTrackingState
        )
    }

    func testDeletingAmbiguousExportRemovesOwnedArtifactAndRetriesLibraryOpen() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let fixture = try makeAmbiguousExportFixture(in: paths.root)
        let model = makeModel(paths)
        try writeEmptyCatalog(to: paths.catalog)
        await model.restoreLibraryOnLaunch()
        XCTAssertEqual(model.libraryLifecycleState, .ready)
        model.blockLibraryAfterIndeterminateExportState()
        model.preserveAmbiguousExportCommitTransactions(from: fixture.report)

        let resolved = await model.resolveAmbiguousExportCommitDeletingOwnedArtifacts(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )

        XCTAssertTrue(resolved)
        XCTAssertEqual(model.libraryLifecycleState, .ready)
        XCTAssertTrue(model.ambiguousExportCommitTransactionIDs.isEmpty)
        XCTAssertTrue(model.preservableExportCommitTransactionIDs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.finalURL.path))
        XCTAssertFalse(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    private func makeModel(_ paths: Paths) -> AppModel {
        AppModel(
            libraryCatalogURL: paths.catalog,
            libraryDefectDirectoryURL: paths.defects,
            libraryBackupDirectoryURL: paths.backups
        )
    }

    private func makePaths() throws -> Paths {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-blocked-recovery-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Paths(
            root: root,
            catalog: root.appendingPathComponent("library.json"),
            defects: root.appendingPathComponent("defects", isDirectory: true),
            backups: root.appendingPathComponent("Backups", isDirectory: true)
        )
    }

    private func writeEmptyCatalog(to url: URL) throws {
        let data = try XCTUnwrap(LibraryCatalogFile.encode(LibraryCatalog()))
        try data.write(to: url, options: .atomic)
    }

    private func makeAmbiguousExportFixture(
        in root: URL,
        label: String = "output"
    ) throws -> AmbiguousExportFixture {
        let journalDirectory = root.appendingPathComponent("journals", isDirectory: true)
        let transactionID = UUID()
        let stagingDirectory = root.appendingPathComponent(
            ".negaflow-export-\(transactionID.uuidString).tmp",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: false
        )
        try ExportArtifactCommitJournal.beginPreparation(
            transactionID: transactionID,
            stagingDirectory: stagingDirectory,
            in: journalDirectory
        )
        let stagedURL = stagingDirectory.appendingPathComponent("\(label).jpg")
        let finalURL = root.appendingPathComponent("\(label).jpg")
        try Data("ambiguous export".utf8).write(to: stagedURL)
        try ExportArtifactCommitJournal.promotePreparation(
            transactionID: transactionID,
            stagingDirectory: stagingDirectory,
            stagedURLs: [stagedURL],
            finalURLs: [finalURL],
            in: journalDirectory
        )
        try ExportArtifactCommitJournal.publish(
            transactionID: transactionID,
            stagedURL: stagedURL,
            finalURL: finalURL,
            in: journalDirectory
        )
        try ExportArtifactCommitJournal.markCatalogCommitIntent(
            transactionID: transactionID,
            in: journalDirectory
        )
        try ExportArtifactCommitJournal.markCatalogCommitAttempted(
            transactionID: transactionID,
            in: journalDirectory
        )
        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: journalDirectory
        )
        XCTAssertTrue(report.ambiguousTransactionIDs.contains(transactionID))
        XCTAssertTrue(report.blockingTransactionIDs.contains(transactionID))
        XCTAssertTrue(report.preservableTransactionIDs.contains(transactionID))
        return AmbiguousExportFixture(
            journalDirectory: journalDirectory,
            transactionID: transactionID,
            finalURL: finalURL,
            report: report
        )
    }

    private struct Paths {
        let root: URL
        let catalog: URL
        let defects: URL
        let backups: URL
    }

    private struct AmbiguousExportFixture {
        let journalDirectory: URL
        let transactionID: UUID
        let finalURL: URL
        let report: ExportArtifactCommitReconciliationReport
    }
}
