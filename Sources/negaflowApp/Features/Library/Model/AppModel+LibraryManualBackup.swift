import Foundation

private struct LibraryManualBackupPayload: Sendable {
    let catalog: LibraryCatalog
    let catalogData: Data
    let defectDataByFrameID: [UUID: Data]

    var requiredDestinationBytes: Int64 {
        LibraryBackupSizeEstimator.requiredBytes(
            catalogData: catalogData,
            defectData: Array(defectDataByFrameID.values)
        )
    }
}

private struct LibraryManualBackupResult: Sendable {
    let generationURL: URL
    let drill: LibraryBackupRestoreDrillResult
}

extension AppModel {
    func refreshExternalBackupDestinationStatus() {
        _ = backupDestinationStore.refresh(catalogURL: libraryCatalogURL)
    }

    func configureExternalBackupDestination(_ url: URL) {
        backupDestinationStore.configure(url)
        refreshExternalBackupDestinationStatus()
    }

    func clearExternalBackupDestination() {
        backupDestinationStore.clear()
    }

    func runScheduledBackupIfDue(at date: Date = Date()) async {
        guard backupScheduleStore.isDue(at: date) else { return }
        _ = await createLibraryBackupNow(at: date)
    }

    @discardableResult
    func createLibraryBackupNow() async -> Bool {
        await createLibraryBackupNow(at: Date())
    }

    @discardableResult
    func createLibraryBackupNow(
        at attemptDate: Date,
        afterFreeze: (() -> Void)? = nil
    ) async -> Bool {
        if let reason = libraryCatalogBlockReason {
            statusMessage = libraryCatalogBlockMessage(reason)
            return false
        }
        guard libraryPersistenceEnabled,
              !isLibraryMaintenanceInProgress,
              !hasUncommittedDefectGesture,
              !isAcknowledgedLibraryTransactionActive else { return false }
        isLibraryMaintenanceInProgress = true
        defer { isLibraryMaintenanceInProgress = false }
        backupScheduleStore.recordAttempt(at: attemptDate)

        librarySaveTask?.cancel()
        librarySaveTask = nil
        guard let payload = makeManualBackupPayload() else {
            return failManualBackup()
        }
        afterFreeze?()

        let usesExternalDestination = backupDestinationStore.isConfigured
        let backupDirectory: URL
        if usesExternalDestination {
            let destinationStatus = backupDestinationStore.refresh(
                catalogURL: libraryCatalogURL,
                requiredBytes: payload.requiredDestinationBytes
            )
            guard destinationStatus.readyInfo != nil,
                  let configuredURL = backupDestinationStore.configuredURL else {
                return failManualBackup()
            }
            backupDirectory = configuredURL
        } else {
            backupDirectory = libraryBackupDirectoryURL
        }

        let result = await createManualBackupSnapshot(
            payload,
            backupDirectory: backupDirectory,
            verificationDate: attemptDate
        )
        if let result, result.drill.succeeded {
            if usesExternalDestination { backupDestinationStore.markSuccess() }
            backupScheduleStore.recordSuccess(result.drill, at: attemptDate)
            statusMessage = text(AppLocalizedPhrase.diskLibraryBackupCreatedStatus)
            return true
        } else if let drill = result?.drill {
            backupScheduleStore.recordFailedDrill(drill)
            _ = failManualBackup()
        } else {
            _ = failManualBackup()
        }
        return false
    }

    private func makeManualBackupPayload() -> LibraryManualBackupPayload? {
        let persistentFrames = frames.filter { !$0.isPreviewScan }
        guard rollStore.hasExactMembership(for: persistentFrames.map(\.id)) else { return nil }
        let catalog = makeLibraryCatalogValue(
            frames: persistentFrames,
            rolls: rolls,
            activeRollID: activeRollID,
            scanSessions: scanSessions,
            scanRollAssignments: scanRollAssignments
        )
        guard let catalogData = LibraryCatalogFile.encode(catalog) else { return nil }
        // 결함 기록은 세션 전용이라 백업에 sidecar를 담지 않는다(종료 시 이미지에 굽힘).
        let defectDataByFrameID: [UUID: Data] = [:]
        return LibraryManualBackupPayload(
            catalog: catalog,
            catalogData: catalogData,
            defectDataByFrameID: defectDataByFrameID
        )
    }

    private func createManualBackupSnapshot(
        _ payload: LibraryManualBackupPayload,
        backupDirectory: URL,
        verificationDate: Date
    ) async -> LibraryManualBackupResult? {
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let sourceRoot = fileManager.temporaryDirectory.appendingPathComponent(
                "negaflow-manual-backup-\(UUID().uuidString)", isDirectory: true
            )
            defer { try? fileManager.removeItem(at: sourceRoot) }
            do {
                let sourceCatalog = sourceRoot.appendingPathComponent("library.json")
                let sourceDefects = sourceRoot.appendingPathComponent("defects", isDirectory: true)
                try fileManager.createDirectory(at: sourceDefects, withIntermediateDirectories: true)
                try payload.catalogData.write(to: sourceCatalog, options: .atomic)
                for (frameID, data) in payload.defectDataByFrameID {
                    try data.write(
                        to: DefectSidecarFile.url(for: frameID, in: sourceDefects),
                        options: .atomic
                    )
                }
                guard LibraryCatalogHealthInspector.inspect(
                    payload.catalog,
                    defectDirectory: sourceDefects,
                    fileManager: fileManager
                ).canOpenSafely else { return nil }
                let generationURL = try LibraryBackupStore.createSnapshot(
                    catalogURL: sourceCatalog,
                    defectDirectory: sourceDefects,
                    backupDirectory: backupDirectory
                )
                return LibraryManualBackupResult(
                    generationURL: generationURL,
                    drill: LibraryBackupRestoreDrill.verify(
                        generationURL: generationURL,
                        now: verificationDate
                    )
                )
            } catch {
                return nil
            }
        }.value
    }

    @discardableResult
    private func failManualBackup() -> Bool {
        statusMessage = text(AppLocalizedPhrase.diskLibraryBackupFailedStatus)
        return false
    }
}
