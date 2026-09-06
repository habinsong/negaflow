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
        guard let payload = await makeManualBackupPayload() else {
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

    private func makeManualBackupPayload() async -> LibraryManualBackupPayload? {
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
        var recipes: [DefectRecipeSnapshot] = []
        for frame in persistentFrames {
            guard !frame.defectEditsNeedRestore else { return nil }
            if !frame.defectEdits.isEmpty {
                guard let snapshot = try? DefectRecipeSnapshot(
                    frameID: frame.id, revision: max(1, frame.defectRecipeRevision),
                    sourceIdentity: frame.defectRecipeIdentity?.sourceIdentity,
                    items: frame.defectEdits.map { DefectEditItemRecord(item: $0) }
                ) else { return nil }
                recipes.append(snapshot)
            }
        }
        let frozenRecipes = recipes
        let encoded = await Task.detached(priority: .utility) { () -> [UUID: Data]? in
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            var result: [UUID: Data] = [:]
            for recipe in frozenRecipes {
                guard let data = try? encoder.encode(DefectSidecarV2(snapshot: recipe)),
                      case .loaded = DefectSidecarFile.decode(data, expectedFrameID: recipe.frameID, limits: .standard)
                else { return nil }
                result[recipe.frameID] = data
            }
            return result
        }.value
        guard let defectDataByFrameID = encoded else { return nil }
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
