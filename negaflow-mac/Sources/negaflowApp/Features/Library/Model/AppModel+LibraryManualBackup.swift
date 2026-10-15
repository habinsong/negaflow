import Foundation

struct LibraryManualBackupPayload: Sendable {
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

private struct PendingBackupRecipe: Sendable {
    let frameID: UUID
    let revision: UInt64
    let sourceIdentity: DefectSourceIdentity?
    let items: [DefectEditItemRecord]
}

struct LibraryManualBackupResult: Sendable {
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
        return await writeLibraryBackup(payload, at: attemptDate, announcesSuccess: true)
    }

    /// 얼린 payload 로 백업 세대를 만들고 복원 시험까지 기록한다. 수동·자동 백업이 함께 쓴다.
    func writeLibraryBackup(
        _ payload: LibraryManualBackupPayload,
        at attemptDate: Date,
        announcesSuccess: Bool
    ) async -> Bool {
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
            if announcesSuccess {
                statusMessage = text(AppLocalizedPhrase.diskLibraryBackupCreatedStatus)
            }
            return true
        } else if let drill = result?.drill {
            backupScheduleStore.recordFailedDrill(drill)
            _ = failManualBackup()
        } else {
            _ = failManualBackup()
        }
        return false
    }

    func makeManualBackupPayload() async -> LibraryManualBackupPayload? {
        let persistentFrames = frames.filter { !$0.isPreviewScan }
        guard rollStore.hasExactMembership(for: persistentFrames.map(\.id)) else { return nil }
        let catalog = makeLibraryCatalogValue(
            frames: persistentFrames,
            rolls: rolls,
            activeRollID: activeRollID,
            scanSessions: scanSessions,
            scanRollAssignments: scanRollAssignments
        )
        // 메인에서는 값만 얼린다. recipe 지문(SHA-256)과 인코딩은 큰 마스크를 통째로 훑으므로
        // 백그라운드에서 한다 — 자동 백업이 실행 중에 돌아도 화면이 멈추지 않게.
        var recipes: [PendingBackupRecipe] = []
        var deferredRecipeFrameIDs: [UUID] = []
        for frame in persistentFrames {
            if frame.defectEditsLoadDeferred {
                // 메모리에 올리지 않은 기록은 디스크 기록을 읽기 검증한 바이트 그대로 담는다.
                deferredRecipeFrameIDs.append(frame.id)
                continue
            }
            guard !frame.defectEditsNeedRestore else { return nil }
            if !frame.defectEdits.isEmpty {
                recipes.append(PendingBackupRecipe(
                    frameID: frame.id,
                    revision: max(1, frame.defectRecipeRevision),
                    sourceIdentity: frame.defectRecipeIdentity?.sourceIdentity,
                    items: frame.defectEdits.map { DefectEditItemRecord(item: $0) }
                ))
            }
        }
        let frozenRecipes = recipes
        let frozenDeferredRecipeFrameIDs = deferredRecipeFrameIDs
        let defectDirectory = libraryDefectDirectoryURL
        return await Task.detached(priority: .utility) { () -> LibraryManualBackupPayload? in
            guard let catalogData = LibraryCatalogFile.encode(catalog) else { return nil }
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            var defectDataByFrameID: [UUID: Data] = [:]
            DefectSidecarFile.flushSync()
            for frameID in frozenDeferredRecipeFrameIDs {
                guard let data = DefectSidecarFile.validatedRawData(for: frameID, in: defectDirectory) else {
                    return nil
                }
                defectDataByFrameID[frameID] = data
            }
            for recipe in frozenRecipes {
                guard let snapshot = try? DefectRecipeSnapshot(
                    frameID: recipe.frameID, revision: recipe.revision,
                    sourceIdentity: recipe.sourceIdentity, items: recipe.items
                ),
                let data = try? encoder.encode(DefectSidecarV2(snapshot: snapshot)),
                case .loaded = DefectSidecarFile.decode(data, expectedFrameID: recipe.frameID, limits: .standard)
                else { return nil }
                defectDataByFrameID[recipe.frameID] = data
            }
            return LibraryManualBackupPayload(
                catalog: catalog,
                catalogData: catalogData,
                defectDataByFrameID: defectDataByFrameID
            )
        }.value
    }

    func createManualBackupSnapshot(
        _ payload: LibraryManualBackupPayload,
        backupDirectory: URL,
        verificationDate: Date
    ) async -> LibraryManualBackupResult? {
        // 수동·자동 백업이 같은 백업 폴더에 동시에 쓰면 세대 번호와 정리가 엉킨다. 한 줄로 세운다.
        await withCheckedContinuation { continuation in
            Self.backupSnapshotQueue.async {
                continuation.resume(returning: Self.writeBackupSnapshot(
                    payload, backupDirectory: backupDirectory, verificationDate: verificationDate
                ))
            }
        }
    }

    private static let backupSnapshotQueueLabel = "negaflow.library-backup-snapshot"
    private static let backupSnapshotQueue = DispatchQueue(label: backupSnapshotQueueLabel, qos: .utility)

    private nonisolated static func writeBackupSnapshot(
        _ payload: LibraryManualBackupPayload,
        backupDirectory: URL,
        verificationDate: Date
    ) -> LibraryManualBackupResult? {
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
    }

    @discardableResult
    func failManualBackup() -> Bool {
        statusMessage = text(AppLocalizedPhrase.diskLibraryBackupFailedStatus)
        return false
    }
}
