import AppKit
import Foundation
import Chromabase

extension AppModel {
    func preserveAmbiguousExportCommitTransactions(
        from report: ExportArtifactCommitReconciliationReport
    ) {
        let ambiguousTransactionIDs = Set(report.ambiguousTransactionIDs)
        ambiguousExportCommitTransactionIDs = ambiguousTransactionIDs.sorted {
            $0.uuidString < $1.uuidString
        }
        let preservableTransactionIDs = Set(report.preservableTransactionIDs)
            .union(report.ambiguousTransactionIDs)
        preservableExportCommitTransactionIDs = preservableTransactionIDs.sorted {
            $0.uuidString < $1.uuidString
        }
    }

    @discardableResult
    func resolveAmbiguousExportCommitPreservingArtifacts(
        transactionID: UUID,
        in journalDirectory: URL = ExportArtifactCommitJournal.defaultDirectoryURL()
    ) async -> Bool {
        guard preservableExportCommitTransactionIDs.contains(transactionID) else {
            return false
        }
        let resolved = await Task.detached(priority: .userInitiated) {
            do {
                try ExportArtifactCommitJournal.resolveAmbiguousCommitPreservingArtifacts(
                    transactionID: transactionID,
                    in: journalDirectory
                )
                return true
            } catch {
                return false
            }
        }.value
        guard resolved else { return false }
        ambiguousExportCommitTransactionIDs.removeAll { $0 == transactionID }
        preservableExportCommitTransactionIDs.removeAll { $0 == transactionID }
        _ = await retryBlockedLibraryOpen(exportJournalDirectory: journalDirectory)
        return true
    }

    @discardableResult
    func resolveAmbiguousExportCommitDeletingOwnedArtifacts(
        transactionID: UUID,
        in journalDirectory: URL = ExportArtifactCommitJournal.defaultDirectoryURL()
    ) async -> Bool {
        guard ambiguousExportCommitTransactionIDs.contains(transactionID) else {
            return false
        }
        let resolved = await Task.detached(priority: .userInitiated) {
            ExportArtifactCommitJournal.resolveAmbiguousCommitDeletingOwnedArtifacts(
                transactionID: transactionID,
                in: journalDirectory
            )
        }.value
        guard resolved else { return false }
        ambiguousExportCommitTransactionIDs.removeAll { $0 == transactionID }
        preservableExportCommitTransactionIDs.removeAll { $0 == transactionID }
        _ = await retryBlockedLibraryOpen(exportJournalDirectory: journalDirectory)
        return true
    }

    @discardableResult
    func retryBlockedLibraryOpen(
        exportJournalDirectory: URL = ExportArtifactCommitJournal.defaultDirectoryURL()
    ) async -> Bool {
        guard libraryLifecycleState == .blocked,
              !isLibraryMaintenanceInProgress else {
            return libraryLifecycleState == .ready
        }
        isLibraryMaintenanceInProgress = true
        defer { isLibraryMaintenanceInProgress = false }

        didRestoreLibrary = false
        await restoreLibraryOnLaunch(
            reusingHeldProcessLock: libraryProcessLock != nil,
            exportJournalDirectory: exportJournalDirectory
        )
        return libraryLifecycleState == .ready
    }

    @discardableResult
    func restoreBlockedLibraryBackup(generationID: String) async throws -> Bool {
        _ = try await scheduleLibraryRestore(generationID: generationID)
        return await retryBlockedLibraryOpen()
    }

    func revealLibraryCatalogInFinder() {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: libraryCatalogURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([libraryCatalogURL])
        } else {
            NSWorkspace.shared.open(libraryCatalogURL.deletingLastPathComponent())
        }
    }

    func libraryRecoveryDiagnostics(
        generations: [LibraryBackupGeneration]
    ) -> LibraryRecoveryDiagnostics {
        LibraryRecoveryDiagnostics(
            appVersion: NegaflowProductVersion.applicationVersion(),
            failureCode: libraryCatalogBlockReason?.diagnosticCode ?? "unknown",
            lifecycleCode: libraryLifecycleState.diagnosticCode,
            catalogPath: abbreviatedPath(libraryCatalogURL),
            backupDirectoryPath: abbreviatedPath(libraryBackupDirectoryURL),
            pendingRestoreID: libraryPendingRestoreMarker?.sourceGenerationID,
            generations: generations
        )
    }

    func copyLibraryRecoveryDiagnostics(
        generations: [LibraryBackupGeneration]
    ) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            libraryRecoveryDiagnostics(generations: generations).text,
            forType: .string
        )
    }

    var abbreviatedLibraryCatalogPath: String {
        abbreviatedPath(libraryCatalogURL)
    }

    private func abbreviatedPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
