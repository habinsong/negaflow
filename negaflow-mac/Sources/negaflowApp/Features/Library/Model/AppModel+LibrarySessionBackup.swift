import Foundation

/// 실행 중 자동 백업. 카탈로그가 저장되고 나면 잠시 뒤 백그라운드로 한 세대를 만든다 — 종료는
/// 백업을 기다리지 않는다. 백업은 메모리 상태를 한 순간 얼린 값으로 만들고, 살아 있는 카탈로그와
/// 결함 기록 파일은 읽지도 쓰지도 않는다. 저장·스캔 발행을 막는 유지보수 표시도 세우지 않는다.
extension AppModel {
    /// 첫 저장부터 잰다. 저장이 계속 이어져도 백업이 끝없이 밀리지 않게 한다.
    static let sessionBackupDelay: Duration = .seconds(120)
    static let sessionBackupRetryDelay: Duration = .seconds(30)
    /// 백업은 결함 기록까지 통째로 복사하는 무거운 일이고 보존 세대도 몇 개뿐이다. 너무 자주 돌면
    /// 디스크를 계속 쓰고, 이전 세션의 세대가 금방 밀려난다.
    static let sessionBackupMinimumInterval: TimeInterval = 60 * 60

    func scheduleSessionBackupAfterSave(now: Date = Date()) {
        guard backupScheduleStore.schedule == .automatic,
              sessionBackupTask == nil,
              libraryPersistenceEnabled,
              !isLibraryTerminationSaveInProgress else { return }
        if let lastAttempt = backupScheduleStore.lastAttemptAt,
           now.timeIntervalSince(lastAttempt) < Self.sessionBackupMinimumInterval {
            return
        }
        sessionBackupTask = Task { [weak self] in
            try? await Task.sleep(for: Self.sessionBackupDelay)
            await self?.runSessionBackupWhenSettled()
        }
    }

    private func runSessionBackupWhenSettled() async {
        defer { sessionBackupTask = nil }
        while !Task.isCancelled {
            guard backupScheduleStore.schedule == .automatic,
                  libraryPersistenceEnabled,
                  libraryCatalogBlockReason == nil,
                  !isLibraryTerminationSaveInProgress else { return }
            if isReadyForSessionBackup {
                await createSessionBackup(at: Date())
                return
            }
            try? await Task.sleep(for: Self.sessionBackupRetryDelay)
        }
    }

    /// 저장할 것이 남았거나 다른 일이 카탈로그를 다루는 중이면 미룬다. 얼리는 값이 디스크에서
    /// 확인된 상태와 같을 때만 뜬다.
    var isReadyForSessionBackup: Bool {
        libraryLifecycleState == .ready
            && !hasUnsavedLibraryChanges
            && librarySaveTask == nil
            && libraryCatalogPersistenceError == nil
            && !isLibraryMaintenanceInProgress
            && !isAcknowledgedLibraryTransactionActive
            && !hasUncommittedDefectGesture
            && !isScanning
            && !isScanFinalizationInProgress
            && !exportBatchStore.isRunning
            && frames.allSatisfy {
                $0.isPreviewScan || $0.defectEdits.isEmpty || isDefectRecipeCommitted($0)
            }
    }

    @discardableResult
    func createSessionBackup(at attemptDate: Date) async -> Bool {
        guard isReadyForSessionBackup else { return false }
        backupScheduleStore.recordAttempt(at: attemptDate)
        guard let payload = await makeManualBackupPayload() else {
            return failManualBackup()
        }
        return await writeLibraryBackup(payload, at: attemptDate, announcesSuccess: false)
    }
}
