import XCTest
import Chromabase
@testable import negaflowApp

final class ExportArtifactCommitJournalTests: XCTestCase {
    func testPreparationMarkerCleansOrphanStagingWithoutTouchingFinalFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-export-preparation-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let journalDirectory = root.appendingPathComponent("journals", isDirectory: true)
        let transactionID = UUID()
        let stagingDirectory = root.appendingPathComponent(
            ".negaflow-export-\(transactionID.uuidString).tmp",
            isDirectory: true
        )
        let finalURL = root.appendingPathComponent("existing-output.tiff")
        let existingData = Data("existing user output".utf8)
        try existingData.write(to: finalURL)

        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: false
        )
        try ExportArtifactCommitJournal.beginPreparation(
            transactionID: transactionID,
            stagingDirectory: stagingDirectory,
            in: journalDirectory
        )
        try Data(repeating: 7, count: 1_024).write(
            to: stagingDirectory.appendingPathComponent("partial-page.tiff")
        )

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: journalDirectory
        )

        XCTAssertEqual(report.completedTransactionIDs, [transactionID])
        XCTAssertTrue(report.unresolvedTransactionIDs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDirectory.path))
        XCTAssertEqual(try Data(contentsOf: finalURL), existingData)
        XCTAssertFalse(ExportArtifactCommitJournal.preparationExists(
            transactionID: transactionID,
            in: journalDirectory
        ))
    }

    func testPreparationMarkerNeverFollowsStagingSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-export-preparation-symlink-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let journalDirectory = root.appendingPathComponent("journals", isDirectory: true)
        let transactionID = UUID()
        let stagingDirectory = root.appendingPathComponent(
            ".negaflow-export-\(transactionID.uuidString).tmp",
            isDirectory: true
        )
        let externalDirectory = root.appendingPathComponent("external", isDirectory: true)
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: false)
        let externalFile = externalDirectory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: externalFile)
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: false
        )
        try ExportArtifactCommitJournal.beginPreparation(
            transactionID: transactionID,
            stagingDirectory: stagingDirectory,
            in: journalDirectory
        )
        try FileManager.default.removeItem(at: stagingDirectory)
        try FileManager.default.createSymbolicLink(
            at: stagingDirectory,
            withDestinationURL: externalDirectory
        )

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: journalDirectory
        )

        XCTAssertEqual(report.unresolvedTransactionIDs, [transactionID])
        XCTAssertEqual(try Data(contentsOf: externalFile), Data("keep".utf8))
        XCTAssertTrue(ExportArtifactCommitJournal.preparationExists(
            transactionID: transactionID,
            in: journalDirectory
        ))
    }

    func testPreparationMarkerPreservesReplacedStagingDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-export-preparation-replaced-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
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
        try FileManager.default.removeItem(at: stagingDirectory)
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: false
        )
        let replacementURL = stagingDirectory.appendingPathComponent("external-replacement")
        let replacement = Data("preserve replacement".utf8)
        try replacement.write(to: replacementURL)

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: journalDirectory
        )

        XCTAssertEqual(report.unresolvedTransactionIDs, [transactionID])
        XCTAssertEqual(try Data(contentsOf: replacementURL), replacement)
        XCTAssertTrue(ExportArtifactCommitJournal.preparationExists(
            transactionID: transactionID,
            in: journalDirectory
        ))
    }

    func testPreparationReconcileCompletesInterruptedStagingQuarantineCleanup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-export-preparation-quarantine-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
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
        try Data("partial render".utf8).write(
            to: stagingDirectory.appendingPathComponent("partial.tiff")
        )
        let quarantineURL = root.appendingPathComponent(
            ".negaflow-staging-cleanup-\(transactionID.uuidString).tmp",
            isDirectory: true
        )
        try ExportArtifactFileOperations.moveExclusively(
            from: stagingDirectory,
            to: quarantineURL
        )

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: journalDirectory
        )

        XCTAssertEqual(report.completedTransactionIDs, [transactionID])
        XCTAssertTrue(report.unresolvedTransactionIDs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: quarantineURL.path))
        XCTAssertFalse(ExportArtifactCommitJournal.preparationExists(
            transactionID: transactionID,
            in: journalDirectory
        ))
    }

    func testPreparationStartRejectsNonemptyStagingWithoutDeletingIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-export-preparation-collision-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
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
        let existingURL = stagingDirectory.appendingPathComponent("existing-user-file")
        let existingData = Data("preserve".utf8)
        try existingData.write(to: existingURL)

        XCTAssertThrowsError(try ExportArtifactCommitJournal.beginPreparation(
            transactionID: transactionID,
            stagingDirectory: stagingDirectory,
            in: journalDirectory
        ))

        XCTAssertEqual(try Data(contentsOf: existingURL), existingData)
        XCTAssertFalse(ExportArtifactCommitJournal.preparationExists(
            transactionID: transactionID,
            in: journalDirectory
        ))
    }

    func testPreparationStartRemovesOwnedStagingWhenMarkerAlreadyExists() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-export-preparation-marker-collision-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let journalDirectory = root.appendingPathComponent("journals", isDirectory: true)
        try FileManager.default.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
        let transactionID = UUID()
        let stagingDirectory = root.appendingPathComponent(
            ".negaflow-export-\(transactionID.uuidString).tmp",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
        let markerURL = journalDirectory.appendingPathComponent("\(transactionID.uuidString).prep")
        let existingMarker = Data("external marker".utf8)
        try existingMarker.write(to: markerURL)

        XCTAssertThrowsError(try ExportArtifactCommitJournal.beginPreparation(
            transactionID: transactionID,
            stagingDirectory: stagingDirectory,
            in: journalDirectory
        ))

        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDirectory.path))
        XCTAssertEqual(try Data(contentsOf: markerURL), existingMarker)
    }

    func testPreparationPromotionRejectsRemovedOwnerWithoutDeletingStaging() throws {
        let fixture = try makePreparationPromotionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try FileManager.default.removeItem(at: fixture.ownerURL)

        XCTAssertThrowsError(try ExportArtifactCommitJournal.promotePreparation(
            transactionID: fixture.transactionID,
            stagingDirectory: fixture.stagingDirectory,
            stagedURLs: [fixture.stagedURL],
            finalURLs: [fixture.finalURL],
            in: fixture.journalDirectory
        ))

        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.stagedURL.path))
        XCTAssertTrue(ExportArtifactCommitJournal.preparationExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
        XCTAssertFalse(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testPreparationPromotionRejectsReplacedOwnerWithoutDeletingStaging() throws {
        let fixture = try makePreparationPromotionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try FileManager.default.removeItem(at: fixture.ownerURL)
        let replacement = Data(UUID().uuidString.utf8)
        try replacement.write(to: fixture.ownerURL)

        XCTAssertThrowsError(try ExportArtifactCommitJournal.promotePreparation(
            transactionID: fixture.transactionID,
            stagingDirectory: fixture.stagingDirectory,
            stagedURLs: [fixture.stagedURL],
            finalURLs: [fixture.finalURL],
            in: fixture.journalDirectory
        ))

        XCTAssertEqual(try Data(contentsOf: fixture.ownerURL), replacement)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.stagedURL.path))
        XCTAssertTrue(ExportArtifactCommitJournal.preparationExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
        XCTAssertFalse(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testPreparationPromotionNeverFollowsOwnedStagingSymlink() throws {
        let fixture = try makePreparationPromotionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let replacementDirectory = fixture.root.appendingPathComponent(
            "external-owned-staging",
            isDirectory: true
        )
        try FileManager.default.moveItem(
            at: fixture.stagingDirectory,
            to: replacementDirectory
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.stagingDirectory,
            withDestinationURL: replacementDirectory
        )
        let preservedStagedURL = replacementDirectory.appendingPathComponent(
            fixture.stagedURL.lastPathComponent
        )
        let preservedData = try Data(contentsOf: preservedStagedURL)

        XCTAssertThrowsError(try ExportArtifactCommitJournal.promotePreparation(
            transactionID: fixture.transactionID,
            stagingDirectory: fixture.stagingDirectory,
            stagedURLs: [fixture.stagedURL],
            finalURLs: [fixture.finalURL],
            in: fixture.journalDirectory
        ))

        XCTAssertEqual(try Data(contentsOf: preservedStagedURL), preservedData)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: replacementDirectory.appendingPathComponent(
                ".negaflow-staging-owner"
            ).path
        ))
        XCTAssertTrue(ExportArtifactCommitJournal.preparationExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
        XCTAssertFalse(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testUncommittedPartialPublishIsRolledBackOnReconcile() throws {
        let fixture = try makeFixture(writeSidecars: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try promoteFixture(fixture)
        try FileManager.default.moveItem(
            at: fixture.stagedLayout.allURLs[0],
            to: fixture.finalLayout.allURLs[0]
        )

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: fixture.journalDirectory
        )

        XCTAssertEqual(report.completedTransactionIDs, [fixture.transactionID])
        XCTAssertTrue(report.unresolvedTransactionIDs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.stagingDirectory.path))
        for url in fixture.finalLayout.allURLs {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
        XCTAssertFalse(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testCommittedPublishIsPreservedAndJournalIsCleared() throws {
        let fixture = try makeFixture(writeSidecars: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try promoteFixture(fixture)
        for (stagedURL, finalURL) in zip(
            fixture.stagedLayout.allURLs,
            fixture.finalLayout.allURLs
        ) {
            try FileManager.default.moveItem(at: stagedURL, to: finalURL)
        }

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [fixture.transactionID],
            in: fixture.journalDirectory
        )

        XCTAssertEqual(report.completedTransactionIDs, [fixture.transactionID])
        XCTAssertTrue(report.unresolvedTransactionIDs.isEmpty)
        for url in fixture.finalLayout.allURLs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
        XCTAssertFalse(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testReconcileNeverDeletesExternallyReplacedDestination() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try promoteFixture(fixture)
        let finalURL = fixture.finalLayout.outputURL
        try FileManager.default.moveItem(
            at: fixture.stagedLayout.outputURL,
            to: finalURL
        )
        let replacement = Data("external replacement".utf8)
        try replacement.write(to: finalURL, options: .atomic)

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: fixture.journalDirectory
        )

        XCTAssertEqual(report.unresolvedTransactionIDs, [fixture.transactionID])
        XCTAssertEqual(try Data(contentsOf: finalURL), replacement)
        XCTAssertTrue(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testRollbackPreservesIdenticalExternalFileThatWonPublishRace() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        let stagedData = try Data(contentsOf: fixture.stagedLayout.outputURL)
        try stagedData.write(to: fixture.finalLayout.outputURL)
        XCTAssertNotEqual(
            ExportArtifactFileIdentityInspector.regularFile(at: fixture.stagedLayout.outputURL),
            ExportArtifactFileIdentityInspector.regularFile(at: fixture.finalLayout.outputURL)
        )

        ExportArtifactCommitJournal.cancelUncommitted(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )

        XCTAssertEqual(try Data(contentsOf: fixture.finalLayout.outputURL), stagedData)
        XCTAssertTrue(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testRollbackRestoresIdenticalReplacementArrivingAfterValidation() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        try ExportArtifactCommitJournal.publish(
            transactionID: fixture.transactionID,
            stagedURL: fixture.stagedLayout.outputURL,
            finalURL: fixture.finalLayout.outputURL,
            in: fixture.journalDirectory
        )
        let publishedIdentity = ExportArtifactFileIdentityInspector.regularFile(
            at: fixture.finalLayout.outputURL
        )
        let publishedData = try Data(contentsOf: fixture.finalLayout.outputURL)
        var replacementIdentity: ExportArtifactFileIdentity?

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: fixture.journalDirectory,
            beforeRollbackClaim: { finalURL in
                try publishedData.write(to: finalURL, options: .atomic)
                replacementIdentity = ExportArtifactFileIdentityInspector.regularFile(at: finalURL)
            }
        )

        XCTAssertEqual(report.unresolvedTransactionIDs, [fixture.transactionID])
        XCTAssertNotEqual(replacementIdentity, publishedIdentity)
        XCTAssertEqual(
            ExportArtifactFileIdentityInspector.regularFile(at: fixture.finalLayout.outputURL),
            replacementIdentity
        )
        XCTAssertEqual(try Data(contentsOf: fixture.finalLayout.outputURL), publishedData)
        XCTAssertTrue(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testReconcileCompletesRollbackClaimInterruptedAfterQuarantineMove() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        try ExportArtifactCommitJournal.publish(
            transactionID: fixture.transactionID,
            stagedURL: fixture.stagedLayout.outputURL,
            finalURL: fixture.finalLayout.outputURL,
            in: fixture.journalDirectory
        )
        let quarantineURL = fixture.root.appendingPathComponent(
            ".negaflow-rollback-\(fixture.transactionID.uuidString)-0.tmp"
        )
        try ExportArtifactFileOperations.moveExclusively(
            from: fixture.finalLayout.outputURL,
            to: quarantineURL
        )

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: fixture.journalDirectory
        )

        XCTAssertEqual(report.completedTransactionIDs, [fixture.transactionID])
        XCTAssertTrue(report.unresolvedTransactionIDs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: quarantineURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.finalLayout.outputURL.path))
        XCTAssertFalse(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testStagingCleanupRestoresReplacementArrivingAfterOwnerValidation() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        let displacedOwnedDirectory = fixture.root.appendingPathComponent(
            "owned-staging-before-race",
            isDirectory: true
        )
        let externalData = Data("external staging replacement".utf8)
        let externalURL = fixture.stagingDirectory.appendingPathComponent("keep.txt")

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: fixture.journalDirectory,
            beforeStagingCleanupClaim: { stagingURL in
                try FileManager.default.moveItem(at: stagingURL, to: displacedOwnedDirectory)
                try FileManager.default.createDirectory(
                    at: stagingURL,
                    withIntermediateDirectories: false
                )
                try externalData.write(to: externalURL)
            }
        )

        XCTAssertEqual(report.unresolvedTransactionIDs, [fixture.transactionID])
        XCTAssertEqual(try Data(contentsOf: externalURL), externalData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: displacedOwnedDirectory.path))
        XCTAssertTrue(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testReconcileCompletesStagingCleanupInterruptedAfterQuarantineMove() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        let quarantineURL = fixture.root.appendingPathComponent(
            ".negaflow-staging-cleanup-\(fixture.transactionID.uuidString).tmp",
            isDirectory: true
        )
        try ExportArtifactFileOperations.moveExclusively(
            from: fixture.stagingDirectory,
            to: quarantineURL
        )

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: fixture.journalDirectory
        )

        XCTAssertEqual(report.completedTransactionIDs, [fixture.transactionID])
        XCTAssertTrue(report.unresolvedTransactionIDs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: quarantineURL.path))
        XCTAssertFalse(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testExclusivePublishRejectsIdenticalExternalDestinationWithoutClobberingIt() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        let stagedData = try Data(contentsOf: fixture.stagedLayout.outputURL)
        try stagedData.write(to: fixture.finalLayout.outputURL)

        XCTAssertThrowsError(try ExportArtifactCommitJournal.publish(
            transactionID: fixture.transactionID,
            stagedURL: fixture.stagedLayout.outputURL,
            finalURL: fixture.finalLayout.outputURL,
            in: fixture.journalDirectory
        ))

        XCTAssertEqual(try Data(contentsOf: fixture.finalLayout.outputURL), stagedData)
        XCTAssertEqual(try Data(contentsOf: fixture.stagedLayout.outputURL), stagedData)
    }

    func testCatalogCommitIntentWithoutCatalogEvidenceRollsBackOwnedArtifact() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        try ExportArtifactCommitJournal.publish(
            transactionID: fixture.transactionID,
            stagedURL: fixture.stagedLayout.outputURL,
            finalURL: fixture.finalLayout.outputURL,
            in: fixture.journalDirectory
        )
        XCTAssertTrue(ExportArtifactCommitJournal.cleanupOwnedStaging(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
        try ExportArtifactCommitJournal.markCatalogCommitIntent(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: fixture.journalDirectory
        )

        XCTAssertEqual(report.completedTransactionIDs, [fixture.transactionID])
        XCTAssertTrue(report.unresolvedTransactionIDs.isEmpty)
        XCTAssertTrue(report.blockingTransactionIDs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.finalLayout.outputURL.path))
        XCTAssertFalse(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testCatalogCommitAttemptedWithoutCatalogEvidenceBlocksAndPreservesArtifact() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        try ExportArtifactCommitJournal.publish(
            transactionID: fixture.transactionID,
            stagedURL: fixture.stagedLayout.outputURL,
            finalURL: fixture.finalLayout.outputURL,
            in: fixture.journalDirectory
        )
        XCTAssertTrue(ExportArtifactCommitJournal.cleanupOwnedStaging(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
        try ExportArtifactCommitJournal.markCatalogCommitIntent(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        try ExportArtifactCommitJournal.markCatalogCommitAttempted(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: fixture.journalDirectory
        )

        XCTAssertEqual(report.unresolvedTransactionIDs, [fixture.transactionID])
        XCTAssertEqual(report.blockingTransactionIDs, [fixture.transactionID])
        XCTAssertEqual(report.ambiguousTransactionIDs, [fixture.transactionID])
        XCTAssertEqual(report.preservableTransactionIDs, [fixture.transactionID])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.finalLayout.outputURL.path))
        XCTAssertTrue(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testPreserveChoiceSurvivesCrashAndNeverTouchesChangedFinalArtifact() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        try ExportArtifactCommitJournal.publish(
            transactionID: fixture.transactionID,
            stagedURL: fixture.stagedLayout.outputURL,
            finalURL: fixture.finalLayout.outputURL,
            in: fixture.journalDirectory
        )
        try ExportArtifactCommitJournal.markCatalogCommitIntent(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        try ExportArtifactCommitJournal.markCatalogCommitAttempted(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        let replacement = Data("user replacement after ambiguous export".utf8)
        try replacement.write(to: fixture.finalLayout.outputURL, options: .atomic)

        XCTAssertThrowsError(try ExportArtifactCommitJournal
            .resolveAmbiguousCommitPreservingArtifacts(
                transactionID: fixture.transactionID,
                in: fixture.journalDirectory,
                afterPreserveIntent: { throw CocoaError(.fileWriteUnknown) }
            ))

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: fixture.journalDirectory
        )
        XCTAssertEqual(report.completedTransactionIDs, [fixture.transactionID])
        XCTAssertTrue(report.unresolvedTransactionIDs.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.finalLayout.outputURL), replacement)
        XCTAssertFalse(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testPreserveChoiceCanRetryAfterDurableIntentFailure() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        try ExportArtifactCommitJournal.publish(
            transactionID: fixture.transactionID,
            stagedURL: fixture.stagedLayout.outputURL,
            finalURL: fixture.finalLayout.outputURL,
            in: fixture.journalDirectory
        )
        try ExportArtifactCommitJournal.markCatalogCommitIntent(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        try ExportArtifactCommitJournal.markCatalogCommitAttempted(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        XCTAssertThrowsError(try ExportArtifactCommitJournal
            .resolveAmbiguousCommitPreservingArtifacts(
                transactionID: fixture.transactionID,
                in: fixture.journalDirectory,
                afterPreserveIntent: { throw CocoaError(.fileWriteUnknown) }
            ))

        XCTAssertNoThrow(try ExportArtifactCommitJournal
            .resolveAmbiguousCommitPreservingArtifacts(
                transactionID: fixture.transactionID,
                in: fixture.journalDirectory
            ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.finalLayout.outputURL.path))
        XCTAssertFalse(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testDeleteChoiceRemovesOnlyOwnedAmbiguousArtifact() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        try ExportArtifactCommitJournal.publish(
            transactionID: fixture.transactionID,
            stagedURL: fixture.stagedLayout.outputURL,
            finalURL: fixture.finalLayout.outputURL,
            in: fixture.journalDirectory
        )
        XCTAssertTrue(ExportArtifactCommitJournal.cleanupOwnedStaging(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
        try ExportArtifactCommitJournal.markCatalogCommitIntent(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        try ExportArtifactCommitJournal.markCatalogCommitAttempted(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )

        XCTAssertTrue(ExportArtifactCommitJournal.resolveAmbiguousCommitDeletingOwnedArtifacts(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.finalLayout.outputURL.path))
        XCTAssertFalse(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testDeleteChoiceCanRetryAfterDurableRollbackIntentFailure() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        try ExportArtifactCommitJournal.publish(
            transactionID: fixture.transactionID,
            stagedURL: fixture.stagedLayout.outputURL,
            finalURL: fixture.finalLayout.outputURL,
            in: fixture.journalDirectory
        )
        XCTAssertTrue(ExportArtifactCommitJournal.cleanupOwnedStaging(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
        try ExportArtifactCommitJournal.markCatalogCommitIntent(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        try ExportArtifactCommitJournal.markCatalogCommitAttempted(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        XCTAssertFalse(ExportArtifactCommitJournal.resolveAmbiguousCommitDeletingOwnedArtifacts(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory,
            beforeRollback: { throw CocoaError(.fileWriteUnknown) }
        ))

        XCTAssertTrue(ExportArtifactCommitJournal.resolveAmbiguousCommitDeletingOwnedArtifacts(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.finalLayout.outputURL.path))
        XCTAssertFalse(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testDeleteChoiceCrashPreservesExternalReplacementOnReconcile() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        try ExportArtifactCommitJournal.publish(
            transactionID: fixture.transactionID,
            stagedURL: fixture.stagedLayout.outputURL,
            finalURL: fixture.finalLayout.outputURL,
            in: fixture.journalDirectory
        )
        XCTAssertTrue(ExportArtifactCommitJournal.cleanupOwnedStaging(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
        try ExportArtifactCommitJournal.markCatalogCommitIntent(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        try ExportArtifactCommitJournal.markCatalogCommitAttempted(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        XCTAssertFalse(ExportArtifactCommitJournal.resolveAmbiguousCommitDeletingOwnedArtifacts(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory,
            beforeRollback: { throw CocoaError(.fileWriteUnknown) }
        ))
        let replacement = Data("external replacement after delete intent".utf8)
        try replacement.write(to: fixture.finalLayout.outputURL, options: .atomic)

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: fixture.journalDirectory
        )

        XCTAssertEqual(report.unresolvedTransactionIDs, [fixture.transactionID])
        XCTAssertTrue(report.blockingTransactionIDs.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.finalLayout.outputURL), replacement)
        XCTAssertTrue(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testCatalogMembershipWithChangedArtifactIsBlocking() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        try ExportArtifactCommitJournal.publish(
            transactionID: fixture.transactionID,
            stagedURL: fixture.stagedLayout.outputURL,
            finalURL: fixture.finalLayout.outputURL,
            in: fixture.journalDirectory
        )
        XCTAssertTrue(ExportArtifactCommitJournal.cleanupOwnedStaging(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
        try ExportArtifactCommitJournal.markCatalogCommitIntent(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        try ExportArtifactCommitJournal.markCatalogCommitAttempted(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        let replacement = Data("changed committed artifact".utf8)
        try replacement.write(to: fixture.finalLayout.outputURL, options: .atomic)

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [fixture.transactionID],
            in: fixture.journalDirectory
        )

        XCTAssertEqual(report.unresolvedTransactionIDs, [fixture.transactionID])
        XCTAssertEqual(report.blockingTransactionIDs, [fixture.transactionID])
        XCTAssertEqual(report.preservableTransactionIDs, [fixture.transactionID])
        XCTAssertEqual(try Data(contentsOf: fixture.finalLayout.outputURL), replacement)
        XCTAssertTrue(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testCommittedArtifactMismatchOffersPreserveOnlyRecovery() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        try ExportArtifactCommitJournal.publish(
            transactionID: fixture.transactionID,
            stagedURL: fixture.stagedLayout.outputURL,
            finalURL: fixture.finalLayout.outputURL,
            in: fixture.journalDirectory
        )
        XCTAssertTrue(ExportArtifactCommitJournal.cleanupOwnedStaging(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
        try ExportArtifactCommitJournal.markCatalogCommitIntent(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        try ExportArtifactCommitJournal.markCatalogCommitAttempted(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        try ExportArtifactCommitJournal.markCatalogCommitted(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        let replacement = Data("replacement after committed acknowledgement".utf8)
        try replacement.write(to: fixture.finalLayout.outputURL, options: .atomic)

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: fixture.journalDirectory
        )

        XCTAssertEqual(report.unresolvedTransactionIDs, [fixture.transactionID])
        XCTAssertEqual(report.blockingTransactionIDs, [fixture.transactionID])
        XCTAssertTrue(report.ambiguousTransactionIDs.isEmpty)
        XCTAssertEqual(report.preservableTransactionIDs, [fixture.transactionID])
        XCTAssertEqual(try Data(contentsOf: fixture.finalLayout.outputURL), replacement)
        XCTAssertTrue(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testRollbackIntentResumesOwnedArtifactQuarantineAfterCrash() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        try ExportArtifactCommitJournal.publish(
            transactionID: fixture.transactionID,
            stagedURL: fixture.stagedLayout.outputURL,
            finalURL: fixture.finalLayout.outputURL,
            in: fixture.journalDirectory
        )
        XCTAssertTrue(ExportArtifactCommitJournal.cleanupOwnedStaging(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
        try ExportArtifactCommitJournal.markCatalogCommitIntent(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        try ExportArtifactCommitJournal.markCatalogCommitAttempted(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        ExportArtifactCommitJournal.cancelCatalogCommitIntent(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory,
            beforeRollback: { throw CocoaError(.fileWriteUnknown) }
        )
        let quarantineURL = fixture.root.appendingPathComponent(
            ".negaflow-rollback-\(fixture.transactionID.uuidString)-0.tmp"
        )
        try ExportArtifactFileOperations.moveExclusively(
            from: fixture.finalLayout.outputURL,
            to: quarantineURL
        )

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: fixture.journalDirectory
        )

        XCTAssertEqual(report.completedTransactionIDs, [fixture.transactionID])
        XCTAssertTrue(report.unresolvedTransactionIDs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: quarantineURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.finalLayout.outputURL.path))
        XCTAssertFalse(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testRollbackIntentRestoresExternalArtifactQuarantineAfterCrash() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        try ExportArtifactCommitJournal.publish(
            transactionID: fixture.transactionID,
            stagedURL: fixture.stagedLayout.outputURL,
            finalURL: fixture.finalLayout.outputURL,
            in: fixture.journalDirectory
        )
        XCTAssertTrue(ExportArtifactCommitJournal.cleanupOwnedStaging(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
        try ExportArtifactCommitJournal.markCatalogCommitIntent(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        ExportArtifactCommitJournal.cancelCatalogCommitIntent(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory,
            beforeRollback: { throw CocoaError(.fileWriteUnknown) }
        )
        let externalData = try Data(contentsOf: fixture.finalLayout.outputURL)
        try externalData.write(to: fixture.finalLayout.outputURL, options: .atomic)
        let externalIdentity = ExportArtifactFileIdentityInspector.regularFile(
            at: fixture.finalLayout.outputURL
        )
        let quarantineURL = fixture.root.appendingPathComponent(
            ".negaflow-rollback-\(fixture.transactionID.uuidString)-0.tmp"
        )
        try ExportArtifactFileOperations.moveExclusively(
            from: fixture.finalLayout.outputURL,
            to: quarantineURL
        )

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: fixture.journalDirectory
        )

        XCTAssertEqual(report.unresolvedTransactionIDs, [fixture.transactionID])
        XCTAssertEqual(
            ExportArtifactFileIdentityInspector.regularFile(at: fixture.finalLayout.outputURL),
            externalIdentity
        )
        XCTAssertEqual(try Data(contentsOf: fixture.finalLayout.outputURL), externalData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: quarantineURL.path))
        XCTAssertTrue(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testRollbackIntentRestoresExternalStagingQuarantineAfterCrash() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        try ExportArtifactCommitJournal.publish(
            transactionID: fixture.transactionID,
            stagedURL: fixture.stagedLayout.outputURL,
            finalURL: fixture.finalLayout.outputURL,
            in: fixture.journalDirectory
        )
        try ExportArtifactCommitJournal.markCatalogCommitIntent(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        ExportArtifactCommitJournal.cancelCatalogCommitIntent(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory,
            beforeRollback: { throw CocoaError(.fileWriteUnknown) }
        )
        let displacedOwnedDirectory = fixture.root.appendingPathComponent(
            "owned-staging-before-intent-rollback",
            isDirectory: true
        )
        try FileManager.default.moveItem(
            at: fixture.stagingDirectory,
            to: displacedOwnedDirectory
        )
        try FileManager.default.createDirectory(
            at: fixture.stagingDirectory,
            withIntermediateDirectories: false
        )
        let externalData = Data("external intent staging".utf8)
        let externalURL = fixture.stagingDirectory.appendingPathComponent("keep.txt")
        try externalData.write(to: externalURL)
        let quarantineURL = fixture.root.appendingPathComponent(
            ".negaflow-staging-cleanup-\(fixture.transactionID.uuidString).tmp",
            isDirectory: true
        )
        try ExportArtifactFileOperations.moveExclusively(
            from: fixture.stagingDirectory,
            to: quarantineURL
        )

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: fixture.journalDirectory
        )

        XCTAssertEqual(report.unresolvedTransactionIDs, [fixture.transactionID])
        XCTAssertEqual(try Data(contentsOf: externalURL), externalData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: displacedOwnedDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: quarantineURL.path))
        XCTAssertTrue(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testDurableCommittedStatePreservesArtifactWithoutCatalogMembership() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        try ExportArtifactCommitJournal.publish(
            transactionID: fixture.transactionID,
            stagedURL: fixture.stagedLayout.outputURL,
            finalURL: fixture.finalLayout.outputURL,
            in: fixture.journalDirectory
        )
        XCTAssertTrue(ExportArtifactCommitJournal.cleanupOwnedStaging(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
        try ExportArtifactCommitJournal.markCatalogCommitIntent(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        try ExportArtifactCommitJournal.markCatalogCommitAttempted(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        try ExportArtifactCommitJournal.markCatalogCommitted(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: fixture.journalDirectory
        )

        XCTAssertEqual(report.completedTransactionIDs, [fixture.transactionID])
        XCTAssertTrue(report.unresolvedTransactionIDs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.finalLayout.outputURL.path))
        XCTAssertFalse(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testCompleteRejectsIdenticalExternalReplacementAndKeepsJournal() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        try FileManager.default.moveItem(
            at: fixture.stagedLayout.outputURL,
            to: fixture.finalLayout.outputURL
        )
        try ExportArtifactCommitJournal.markCatalogCommitIntent(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        )
        let publishedIdentity = ExportArtifactFileIdentityInspector.regularFile(
            at: fixture.finalLayout.outputURL
        )
        let publishedData = try Data(contentsOf: fixture.finalLayout.outputURL)
        try publishedData.write(to: fixture.finalLayout.outputURL, options: .atomic)
        XCTAssertNotEqual(
            ExportArtifactFileIdentityInspector.regularFile(at: fixture.finalLayout.outputURL),
            publishedIdentity
        )

        XCTAssertThrowsError(try ExportArtifactCommitJournal.complete(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))

        XCTAssertEqual(try Data(contentsOf: fixture.finalLayout.outputURL), publishedData)
        XCTAssertTrue(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testCatalogIntentRejectsPathReplacementDuringArtifactHash() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        try ExportArtifactCommitJournal.publish(
            transactionID: fixture.transactionID,
            stagedURL: fixture.stagedLayout.outputURL,
            finalURL: fixture.finalLayout.outputURL,
            in: fixture.journalDirectory
        )
        XCTAssertTrue(ExportArtifactCommitJournal.cleanupOwnedStaging(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
        let originalIdentity = ExportArtifactFileIdentityInspector.regularFile(
            at: fixture.finalLayout.outputURL
        )
        let originalData = try Data(contentsOf: fixture.finalLayout.outputURL)

        XCTAssertThrowsError(try ExportArtifactCommitJournal.markCatalogCommitIntent(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory,
            afterArtifactIdentityRead: { finalURL in
                try originalData.write(to: finalURL, options: .atomic)
            }
        ))

        XCTAssertNotEqual(
            ExportArtifactFileIdentityInspector.regularFile(at: fixture.finalLayout.outputURL),
            originalIdentity
        )
        XCTAssertEqual(try Data(contentsOf: fixture.finalLayout.outputURL), originalData)
        XCTAssertTrue(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testLegacyOwnerlessJournalPreservesReplacedStagingDirectory() throws {
        let fixture = try makeLegacyFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try FileManager.default.removeItem(at: fixture.stagingDirectory)
        try FileManager.default.createDirectory(
            at: fixture.stagingDirectory,
            withIntermediateDirectories: false
        )
        let externalURL = fixture.stagingDirectory.appendingPathComponent("external-user-file")
        let externalData = Data("preserve legacy replacement".utf8)
        try externalData.write(to: externalURL)

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: fixture.journalDirectory
        )

        XCTAssertEqual(report.unresolvedTransactionIDs, [fixture.transactionID])
        XCTAssertEqual(try Data(contentsOf: externalURL), externalData)
        XCTAssertTrue(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testLegacyOwnerlessJournalNeverFollowsReplacementSymlink() throws {
        let fixture = try makeLegacyFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let externalDirectory = fixture.root.appendingPathComponent("external", isDirectory: true)
        try FileManager.default.createDirectory(
            at: externalDirectory,
            withIntermediateDirectories: false
        )
        let externalURL = externalDirectory.appendingPathComponent("keep.txt")
        let externalData = Data("keep legacy symlink target".utf8)
        try externalData.write(to: externalURL)
        try FileManager.default.removeItem(at: fixture.stagingDirectory)
        try FileManager.default.createSymbolicLink(
            at: fixture.stagingDirectory,
            withDestinationURL: externalDirectory
        )

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: fixture.journalDirectory
        )

        XCTAssertEqual(report.unresolvedTransactionIDs, [fixture.transactionID])
        XCTAssertEqual(try Data(contentsOf: externalURL), externalData)
        XCTAssertTrue(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testPromotionOverlapReconcilesPublishJournalBeforePreparationMarker() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let markerURL = fixture.journalDirectory.appendingPathComponent(
            "\(fixture.transactionID.uuidString).prep"
        )
        let markerData = try Data(contentsOf: markerURL)
        try promoteFixture(fixture)
        try markerData.write(to: markerURL)
        try FileManager.default.moveItem(
            at: fixture.stagedLayout.outputURL,
            to: fixture.finalLayout.outputURL
        )

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: fixture.journalDirectory
        )

        XCTAssertEqual(report.completedTransactionIDs, [fixture.transactionID])
        XCTAssertTrue(report.unresolvedTransactionIDs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.finalLayout.outputURL.path))
        XCTAssertFalse(ExportArtifactCommitJournal.journalExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
        XCTAssertFalse(ExportArtifactCommitJournal.preparationExists(
            transactionID: fixture.transactionID,
            in: fixture.journalDirectory
        ))
    }

    func testLegacyJournalWithoutFileIdentityDecodesAndPreservesFinalArtifact() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-legacy-export-journal-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let journalDirectory = root.appendingPathComponent("journals", isDirectory: true)
        try FileManager.default.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
        let transactionID = UUID()
        let stagingDirectory = root.appendingPathComponent(
            ".negaflow-export-\(UUID().uuidString).tmp",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
        let stagedURL = stagingDirectory.appendingPathComponent("legacy.jpg")
        let finalURL = root.appendingPathComponent("legacy.jpg")
        let data = Data("legacy published artifact".utf8)
        try data.write(to: stagedURL)
        let record = LegacyRecord(
            version: 1,
            transactionID: transactionID,
            stagingDirectoryPath: stagingDirectory.path,
            stagingOwnerIdentity: nil,
            artifacts: [LegacyArtifact(
                stagedPath: stagedURL.path,
                finalPath: finalURL.path,
                identity: try RenderManifest.sourceIdentity(for: stagedURL)
            )]
        )
        try FileManager.default.moveItem(at: stagedURL, to: finalURL)
        try FileManager.default.removeItem(at: stagingDirectory)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(record).write(
            to: journalDirectory.appendingPathComponent("\(transactionID.uuidString).plist")
        )

        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [],
            in: journalDirectory
        )

        XCTAssertEqual(report.unresolvedTransactionIDs, [transactionID])
        XCTAssertEqual(try Data(contentsOf: finalURL), data)
        XCTAssertTrue(ExportArtifactCommitJournal.journalExists(
            transactionID: transactionID,
            in: journalDirectory
        ))
    }

    func testNewJournalUsesDowngradeSafeVersion() throws {
        let fixture = try makeFixture(writeSidecars: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try promoteFixture(fixture)
        let journalURL = fixture.journalDirectory.appendingPathComponent(
            "\(fixture.transactionID.uuidString).plist"
        )
        let header = try PropertyListDecoder().decode(
            JournalVersionHeader.self,
            from: Data(contentsOf: journalURL)
        )

        XCTAssertEqual(header.version, 2)
    }

    func testPackageJournalPreservesMoreThanFiveCommittedPages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-package-journal-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let journalDirectory = root.appendingPathComponent("journals", isDirectory: true)
        let transactionID = UUID()
        let stagingDirectory = root.appendingPathComponent(
            ".negaflow-export-\(transactionID.uuidString).tmp",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try ExportArtifactCommitJournal.beginPreparation(
            transactionID: transactionID,
            stagingDirectory: stagingDirectory,
            in: journalDirectory
        )
        let stagedURLs = (0..<8).map {
            stagingDirectory.appendingPathComponent("page-\($0).jpg")
        }
        let finalURLs = (0..<8).map { root.appendingPathComponent("page-\($0).jpg") }
        for (index, url) in stagedURLs.enumerated() {
            try Data("page-\(index)".utf8).write(to: url)
        }
        try ExportArtifactCommitJournal.promotePreparation(
            transactionID: transactionID,
            stagingDirectory: stagingDirectory,
            stagedURLs: stagedURLs,
            finalURLs: finalURLs,
            in: journalDirectory
        )
        for (stagedURL, finalURL) in zip(stagedURLs, finalURLs) {
            try FileManager.default.moveItem(at: stagedURL, to: finalURL)
        }
        let report = ExportArtifactCommitJournal.reconcile(
            committedTransactionIDs: [transactionID],
            in: journalDirectory
        )

        XCTAssertEqual(report.completedTransactionIDs, [transactionID])
        XCTAssertTrue(report.unresolvedTransactionIDs.isEmpty)
        XCTAssertTrue(finalURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    private struct Fixture {
        let root: URL
        let journalDirectory: URL
        let stagingDirectory: URL
        let transactionID: UUID
        let finalLayout: ExportArtifactLayout
        let stagedLayout: ExportArtifactLayout
    }

    private struct LegacyArtifact: Codable {
        let stagedPath: String
        let finalPath: String
        let identity: RenderManifest.SourceIdentity
    }

    private struct JournalVersionHeader: Codable {
        let version: Int
    }

    private struct LegacyRecord: Codable {
        let version: Int
        let transactionID: UUID
        let stagingDirectoryPath: String
        let stagingOwnerIdentity: RenderManifest.SourceIdentity?
        let artifacts: [LegacyArtifact]
    }

    private struct PreparationPromotionFixture {
        let root: URL
        let journalDirectory: URL
        let stagingDirectory: URL
        let transactionID: UUID
        let ownerURL: URL
        let stagedURL: URL
        let finalURL: URL
    }

    private func makePreparationPromotionFixture() throws -> PreparationPromotionFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-export-promotion-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let journalDirectory = root.appendingPathComponent("journals", isDirectory: true)
        let transactionID = UUID()
        let stagingDirectory = root.appendingPathComponent(
            ".negaflow-export-\(transactionID.uuidString).tmp",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
        try ExportArtifactCommitJournal.beginPreparation(
            transactionID: transactionID,
            stagingDirectory: stagingDirectory,
            in: journalDirectory
        )
        let stagedURL = stagingDirectory.appendingPathComponent("output.tiff")
        try Data("staged output".utf8).write(to: stagedURL)
        return PreparationPromotionFixture(
            root: root,
            journalDirectory: journalDirectory,
            stagingDirectory: stagingDirectory,
            transactionID: transactionID,
            ownerURL: stagingDirectory.appendingPathComponent(".negaflow-staging-owner"),
            stagedURL: stagedURL,
            finalURL: root.appendingPathComponent("output.tiff")
        )
    }

    private func makeFixture(writeSidecars: Bool) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-export-journal-\(UUID().uuidString)",
            isDirectory: true
        )
        let journalDirectory = root.appendingPathComponent("journals", isDirectory: true)
        let transactionID = UUID()
        let stagingDirectory = root.appendingPathComponent(
            ".negaflow-export-\(transactionID.uuidString).tmp",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try ExportArtifactCommitJournal.beginPreparation(
            transactionID: transactionID,
            stagingDirectory: stagingDirectory,
            in: journalDirectory
        )
        let sourceURL = root.appendingPathComponent("source.tiff")
        try Data("source".utf8).write(to: sourceURL)
        let finalLayout = ExportArtifactLayout(
            outputURL: root.appendingPathComponent("output.jpg"),
            format: .jpeg,
            sourceURL: sourceURL,
            writeSidecar: writeSidecars,
            writeMainFlatMaster: writeSidecars,
            writeOriginalRaw: writeSidecars
        )
        let stagedLayout = finalLayout.staged(in: stagingDirectory)
        for (index, url) in stagedLayout.allURLs.enumerated() {
            try Data("artifact-\(index)".utf8).write(to: url)
        }
        return Fixture(
            root: root,
            journalDirectory: journalDirectory,
            stagingDirectory: stagingDirectory,
            transactionID: transactionID,
            finalLayout: finalLayout,
            stagedLayout: stagedLayout
        )
    }

    private func promoteFixture(_ fixture: Fixture) throws {
        try ExportArtifactCommitJournal.promotePreparation(
            transactionID: fixture.transactionID,
            stagingDirectory: fixture.stagingDirectory,
            stagedLayout: fixture.stagedLayout,
            finalLayout: fixture.finalLayout,
            in: fixture.journalDirectory
        )
    }

    private func makeLegacyFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-legacy-ownerless-journal-\(UUID().uuidString)",
            isDirectory: true
        )
        let journalDirectory = root.appendingPathComponent("journals", isDirectory: true)
        let transactionID = UUID()
        let stagingDirectory = root.appendingPathComponent(
            ".negaflow-export-\(UUID().uuidString).tmp",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("source.tiff")
        try Data("source".utf8).write(to: sourceURL)
        let finalLayout = ExportArtifactLayout(
            outputURL: root.appendingPathComponent("output.jpg"),
            format: .jpeg,
            sourceURL: sourceURL,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false
        )
        let stagedLayout = finalLayout.staged(in: stagingDirectory)
        try Data("legacy staged artifact".utf8).write(to: stagedLayout.outputURL)
        try ExportArtifactCommitJournal.begin(
            transactionID: transactionID,
            stagingDirectory: stagingDirectory,
            stagedLayout: stagedLayout,
            finalLayout: finalLayout,
            in: journalDirectory
        )
        return Fixture(
            root: root,
            journalDirectory: journalDirectory,
            stagingDirectory: stagingDirectory,
            transactionID: transactionID,
            finalLayout: finalLayout,
            stagedLayout: stagedLayout
        )
    }
}
