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
        generations: [LibraryBackupGeneration],
        catalogInspection: LibraryRecoveryCatalogInspection? = nil
    ) -> LibraryRecoveryDiagnostics {
        LibraryRecoveryDiagnostics(
            appVersion: NegaflowProductVersion.applicationVersion(),
            failureCode: libraryCatalogBlockReason?.diagnosticCode ?? "unknown",
            lifecycleCode: libraryLifecycleState.diagnosticCode,
            catalogPath: abbreviatedPath(libraryCatalogURL),
            backupDirectoryPath: abbreviatedPath(libraryBackupDirectoryURL),
            pendingRestoreID: libraryPendingRestoreMarker?.sourceGenerationID,
            generations: generations,
            catalogInspection: catalogInspection,
            repairSummary: libraryCatalogRepairReport?.summaryComponents ?? []
        )
    }

    func copyLibraryRecoveryDiagnostics(
        generations: [LibraryBackupGeneration]
    ) async {
        let catalogURL = libraryCatalogURL
        let defectDirectory = libraryDefectDirectoryURL
        let inspection = await Task.detached(priority: .userInitiated) {
            LibraryRecoveryCatalogInspection.inspect(
                catalogURL: catalogURL,
                defectDirectory: defectDirectory
            )
        }.value
        let text = libraryRecoveryDiagnostics(
            generations: generations,
            catalogInspection: inspection
        ).text
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// 마지막 탈출구. 지금 카탈로그와 결함 기록을 옆에 보관하고 빈 카탈로그로 다시 연다.
    /// 사진 원본과 백업 세대는 건드리지 않는다 — 나중에 백업에서 되돌릴 수 있어야 한다.
    @discardableResult
    func startFreshLibraryFromRecovery() async -> Bool {
        guard libraryLifecycleState == .blocked,
              !isLibraryMaintenanceInProgress else { return false }
        isLibraryMaintenanceInProgress = true
        let catalogURL = libraryCatalogURL
        let defectDirectory = libraryDefectDirectoryURL
        let prepared = await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            do {
                try LibraryBackupStore.preserveUnsafeState(
                    catalogURL: catalogURL,
                    defectDirectory: defectDirectory,
                    fileManager: fileManager
                )
            } catch {
                return false
            }
            if fileManager.fileExists(atPath: catalogURL.path) {
                guard (try? fileManager.removeItem(at: catalogURL)) != nil else { return false }
            }
            if fileManager.fileExists(atPath: defectDirectory.path) {
                try? fileManager.removeItem(at: defectDirectory)
            }
            try? fileManager.createDirectory(
                at: defectDirectory,
                withIntermediateDirectories: true
            )
            // 빈 카탈로그를 직접 세워 둔다. 그냥 지우기만 하면 유효하지 않은 백업 세대가
            // 남아 있을 때 다시 차단 화면으로 돌아온다.
            return LibraryCatalogFile.writeAndVerify(
                LibraryCatalog(),
                to: catalogURL,
                fileManager: fileManager
            )
        }.value
        isLibraryMaintenanceInProgress = false
        guard prepared else { return false }
        return await retryBlockedLibraryOpen()
    }

    var abbreviatedLibraryCatalogPath: String {
        abbreviatedPath(libraryCatalogURL)
    }

    private func abbreviatedPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
