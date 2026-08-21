import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

enum ExportCatalogCommitOutcome: Equatable {
    case committed
    case definitelyNotCommitted
    case indeterminate
}

struct ExportScanSourceSnapshot: Sendable, Equatable {
    let sessionID: UUID
    let jobID: UUID
    let device: ScannerDescriptor
    let backend: ScanBackendSnapshot
}

extension AppModel {
    /// 설정된 내보내기 폴더에 현재 내보내기 설정(format/color/dpi/size)으로 저장한다. 상단 Export
    /// 버튼과 좌측탭 Output의 Export 버튼이 공유한다(저장 패널 없음 — 폴더는 Output 탭에서 변경).
    func exportToFolder(_ frame: ScanFrame) {
        guard ExportNamingTemplate.isValid(exportNamingTemplate) else { return }
        let printerOutputProfile = selectedPrinterOutputProfile
        if exportFormat != .rawScanTIFF,
           frame.params.developTarget == .print,
           printerOutputProfile == nil {
            statusMessage = text(.printOutputProfileRequired)
            return
        }
        let date = Date()
        let identity = currentExportRecipeIdentity(
            outputProfileSHA256: frame.params.developTarget == .print
                ? printerOutputProfile?.profileSHA256
                : nil
        )
        let folder = exportDestinationFolder(root: exportFolderURL, frame: frame, date: date)
        let url = uniqueExportURL(
            in: folder,
            baseName: exportBaseName(
                for: frame,
                namingTemplate: exportNamingTemplate,
                sequence: exportSequenceStart,
                date: date,
                recipeIdentity: identity
            ),
            frame: frame,
            format: exportFormat,
            writeSidecar: exportWriteSidecar,
            writeMainFlatMaster: exportWriteMainFlatMaster,
            writeOriginalRaw: exportWriteOriginalRaw
        )
        exportFrame(
            frame,
            to: url,
            format: exportFormat,
            writeSidecar: exportWriteSidecar,
            writeMainFlatMaster: exportWriteMainFlatMaster,
            writeOriginalRaw: exportWriteOriginalRaw,
            options: exportOptions,
            recipeIdentity: identity
        )
    }

    /// Quick Export: 미리 선택된 빠른 내보내기 폴더에 미리 선택된 포맷/DPI로 즉시 저장한다.
    func quickExport(_ frame: ScanFrame) {
        let printerOutputProfile = selectedPrinterOutputProfile
        if quickExportFormat != .rawScanTIFF,
           frame.params.developTarget == .print,
           printerOutputProfile == nil {
            statusMessage = text(.printOutputProfileRequired)
            return
        }
        let date = Date()
        let identity = quickExportRecipeIdentity(
            outputProfileSHA256: frame.params.developTarget == .print
                ? printerOutputProfile?.profileSHA256
                : nil
        )
        let folder = exportDestinationFolder(root: quickExportFolderURL, frame: frame, date: date)
        let url = uniqueExportURL(
            in: folder,
            baseName: exportBaseName(
                for: frame,
                namingTemplate: ExportNamingTemplate.defaultPattern,
                sequence: 1,
                date: date,
                recipeIdentity: identity
            ),
            frame: frame,
            format: quickExportFormat,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false
        )
        exportFrame(
            frame,
            to: url,
            format: quickExportFormat,
            writeSidecar: false,
            options: quickExportOptions,
            recipeIdentity: identity
        )
    }

    /// 내보내기 대상 폴더: <루트>/<오늘 날짜>/<출처 폴더>. 사용 시점에 생성한다.
    /// 출처 폴더 = 원본이 있던 폴더명 / 스캐너 축약명.
    func exportDestinationFolder(root: URL, frame: ScanFrame, date: Date = Date()) -> URL {
        let folder = root
            .appendingPathComponent(FrameStorageNaming.dateFolderName(for: date), isDirectory: true)
            .appendingPathComponent(exportStorageGroupName(for: frame), isDirectory: true)
        // 폴더를 못 만들면 그대로 진행해봐야 한참 뒤 엉뚱한 오류로 나타난다. 외장 디스크가 빠졌거나
        // 쓰기 권한이 없는 경우가 여기서 걸리므로, 경로와 시스템 오류를 그 자리에서 보고한다.
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            statusMessage = text(
                AppLocalizedPhrase.exportFolderUnavailableFormat,
                folder.path,
                (error as NSError).localizedDescription
            ) + " " + Self.exportVolumeDiagnostic(for: folder)
        }
        return folder
    }

    /// 내보내기·Finder 열기가 함께 쓰는 출처 폴더명. 예전 가져오기가 `default` 로 묶어 둔
    /// 프레임도 원본이 있던 폴더로 해석해, 같은 폴더의 사진이 두 곳으로 갈라지지 않게 한다.
    func exportStorageGroupName(for frame: ScanFrame) -> String {
        FrameStorageNaming.resolvedGroupName(
            storedGroup: frame.storageGroupName,
            sourceURL: frame.rawScanURL
        )
    }

    /// 스캔 당시 영속 세션에 고정된 장치/백엔드만 내보내기 provenance로 사용한다.
    /// 현재 선택 장치는 앱 재시작이나 장치 전환 뒤 달라질 수 있고, legacy/import 프레임에는
    /// 검증 가능한 세션이 없으므로 추정값을 기록하지 않는다.
    func exportScanSourceSnapshot(for frame: ScanFrame) -> ExportScanSourceSnapshot? {
        guard frame.sourceKind == .scannerTIFF,
              let sessionID = frame.scanSessionID,
              let jobID = frame.scanJobID else {
            return nil
        }
        let matchingSessions = scanSessions.filter { $0.id == sessionID }
        guard matchingSessions.count == 1, let session = matchingSessions.first else { return nil }
        let matchingJobs = session.jobs.filter { $0.id == jobID }
        guard matchingJobs.count == 1,
              let job = matchingJobs.first,
              job.kind == .full,
              job.state == .succeeded,
              job.captureManifest != nil else {
            return nil
        }
        return ExportScanSourceSnapshot(
            sessionID: sessionID,
            jobID: jobID,
            device: session.device,
            backend: session.backend
        )
    }

    /// primary뿐 아니라 main-flat/original/JSON/XMP 전체가 비어 있는 basename을 고른다.
    /// 내보내기가 실패했을 때 어느 볼륨에서 막혔는지 실기 없이 판정할 수 있도록 남기는 기술 정보.
    /// 사용자 문구가 아니라 진단 토큰이므로 번역하지 않는다.
    static func exportVolumeDiagnostic(for url: URL, fileManager: FileManager = .default) -> String {
        var probe = url.standardizedFileURL
        while !fileManager.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe = probe.deletingLastPathComponent()
        }
        let values = try? probe.resourceValues(forKeys: [
            .volumeNameKey,
            .volumeLocalizedFormatDescriptionKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeIsReadOnlyKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ])
        let free = values?.volumeAvailableCapacityForImportantUsage
        return String(
            format: "[vol=%@ fs=%@ internal=%@ removable=%@ readonly=%@ writable=%@ free=%@ probed=%@]",
            values?.volumeName ?? "?",
            values?.volumeLocalizedFormatDescription ?? "?",
            values?.volumeIsInternal.map { $0 ? "yes" : "no" } ?? "?",
            values?.volumeIsRemovable.map { $0 ? "yes" : "no" } ?? "?",
            values?.volumeIsReadOnly.map { $0 ? "yes" : "no" } ?? "?",
            fileManager.isWritableFile(atPath: probe.path) ? "yes" : "no",
            free.map { "\($0 / 1_048_576)MB" } ?? "?",
            probe.path
        )
    }

    func uniqueExportURL(
        in folder: URL,
        baseName: String,
        frame: ScanFrame,
        format: ExportFormat,
        writeSidecar: Bool,
        writeMainFlatMaster: Bool,
        writeOriginalRaw: Bool,
        excluding plannedArtifactPaths: Set<String> = []
    ) -> URL {
        var index = 0
        while true {
            let suffix = index == 0 ? "" : "-\(index)"
            let candidate = folder.appendingPathComponent(
                "\(baseName)\(suffix).\(format.fileExtension)"
            )
            let layout = ExportArtifactLayout(
                outputURL: candidate,
                format: format,
                sourceURL: frame.rawScanURL,
                writeSidecar: writeSidecar,
                writeMainFlatMaster: writeMainFlatMaster,
                writeOriginalRaw: writeOriginalRaw
            )
            if exportArtifactsAreAvailable(layout, excluding: plannedArtifactPaths) {
                return candidate
            }
            index += 1
        }
    }

    func exportFrame(_ frame: ScanFrame, to url: URL, format: ExportFormat, writeSidecar: Bool = false,
                     writeMainFlatMaster: Bool = false,
                     writeOriginalRaw: Bool = false,
                     options: ExportOptions = .standard,
                     recipeIdentity: ExportRecipeIdentity? = nil) {
        let printerOutputProfile = selectedPrinterOutputProfile
        if format != .rawScanTIFF,
           frame.params.developTarget == .print,
           printerOutputProfile == nil {
            statusMessage = text(.printOutputProfileRequired)
            return
        }
        frame.isDeveloping = true
        statusMessage = text(AppLocalizedPhrase.exportingStatus)
        Task {
            _ = await runExportFrameTransaction(
                frame,
                to: url,
                format: format,
                writeSidecar: writeSidecar,
                writeMainFlatMaster: writeMainFlatMaster,
                writeOriginalRaw: writeOriginalRaw,
                options: options,
                printerOutputProfile: printerOutputProfile,
                recipeIdentity: recipeIdentity,
                reportsGlobalStatus: true
            )
        }
    }

    /// 파일 publish 뒤 event를 먼저 MainActor 상태에 적용하고, 같은 generation을 디스크에서
    /// read-back 검증한다. 확정 실패만 event를 되돌리고 rollback 결과가 불명확하면 library를
    /// 차단한 채 event와 산출물을 보존한다.
    func commitSuccessfulExportEvent(
        _ event: LibraryExportEvent,
        for frame: ScanFrame,
        trackingIdentity: ExportFrameTrackingIdentity,
        format: ExportFormat,
        sourceGeneration: ExportFrameSourceGeneration,
        sourceVerification: ExportFrameSourceVerification?,
        catalogCommit: (() -> Result<Void, LibraryCatalogCommitError>)? = nil
    ) -> ExportCatalogCommitOutcome {
        guard beginAcknowledgedLibraryTransaction() else { return .definitelyNotCommitted }
        defer { endAcknowledgedLibraryTransaction() }
        guard sourceGeneration.matchesCurrentState(
            of: frame,
            trackingIdentity: trackingIdentity,
            format: format,
            isOwnedByModel: ownsFrame(frame),
            verification: sourceVerification
        ) else {
            return .definitelyNotCommitted
        }

        var state = frame.libraryWorkflowTrackingState
            ?? .newFrame(currentRecipeSHA256: trackingIdentity.developRecipeSHA256)
        let previousExportTracking = state.exportTracking
        state.exportTracking.coverage = .tracked
        state.exportTracking.successfulEvents.append(event)
        frame.libraryWorkflowTrackingState = state

        let commitResult = catalogCommit?() ?? commitAcknowledgedLibrarySnapshot(
            frames: frames,
            rolls: rolls,
            activeRollID: activeRollID,
            scanSessions: scanSessions,
            scanRollAssignments: scanRollAssignments
        )
        switch commitResult {
        case .success:
            acknowledgeCurrentLibraryStateMatchesCommittedSnapshot()
            return .committed
        case .failure(.rollbackFailed):
            blockLibraryAfterIndeterminateExportState()
            return .indeterminate
        case .failure:
            if var rollbackState = frame.libraryWorkflowTrackingState {
                rollbackState.exportTracking = previousExportTracking
                frame.libraryWorkflowTrackingState = rollbackState
            }
            return .definitelyNotCommitted
        }
    }

    func blockLibraryAfterIndeterminateExportState() {
        librarySaveTask?.cancel()
        librarySaveTask = nil
        libraryCatalogBlockReason = .writeFailed
        libraryPersistenceEnabled = false
        transitionLibraryLifecycle(to: .blocked)
        statusMessage = libraryCatalogBlockMessage(.writeFailed)
    }

    @discardableResult
    func blockLibraryForInconsistentExportReconciliation(
        _ report: ExportArtifactCommitReconciliationReport
    ) -> Bool {
        guard !report.blockingTransactionIDs.isEmpty else { return false }
        blockLibraryAfterIndeterminateExportState()
        return true
    }

    func finalizeCommittedExport(
        transactionID: UUID,
        completion: ((UUID) async throws -> Void)? = nil
    ) async -> Bool {
        do {
            if let completion {
                try await completion(transactionID)
            } else {
                try await ExportArtifactCommitJournal.completeAsync(
                    transactionID: transactionID,
                    level: exportVerificationLevel
                )
            }
            return true
        } catch {
            blockLibraryAfterIndeterminateExportState()
            return false
        }
    }

    /// Catalog 성공을 확인한 MainActor turn 안에서 yield 없이 committed journal 상태를 남긴다.
    /// 이후 hash 검증/정리는 background에서 이어가도 frame 제거가 복구 증거를 없앨 수 없다.
    func acknowledgeCommittedExport(transactionID: UUID) -> Bool {
        do {
            try ExportArtifactCommitJournal.markCatalogCommitted(
                transactionID: transactionID
            )
            return true
        } catch {
            blockLibraryAfterIndeterminateExportState()
            return false
        }
    }

    func exportArtifactsAreAvailable(
        _ layout: ExportArtifactLayout,
        excluding plannedArtifactPaths: Set<String> = []
    ) -> Bool {
        let paths = layout.standardizedPaths
        guard paths.count == layout.allURLs.count,
              plannedArtifactPaths.isDisjoint(with: paths),
              reservedExportArtifactPaths.isDisjoint(with: paths) else {
            return false
        }
        return layout.allURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }
    }

    func reserveExportArtifacts(_ layout: ExportArtifactLayout) -> Bool {
        guard exportArtifactsAreAvailable(layout) else { return false }
        reservedExportArtifactPaths.formUnion(layout.standardizedPaths)
        return true
    }

    func releaseExportArtifacts(_ layout: ExportArtifactLayout) {
        reservedExportArtifactPaths.subtract(layout.standardizedPaths)
    }

    /// iCloud 가 로컬 사본을 내린 원본을 먼저 받아둔다. 받는 동안 무엇을 기다리는지 상태로 알린다.
    /// 로컬 파일만 있으면 즉시 true 를 돌려주므로 일반 경로에는 비용이 없다.
    @discardableResult
    func materializeExportSources(
        _ urls: [URL],
        reportsGlobalStatus: Bool
    ) async -> Bool {
        // 축출 여부 확인은 파일 시스템을 만지므로 여기서 미리 하지 않는다 — materialize 가
        // 백그라운드에서 같은 판정을 하고, 로컬뿐이면 진행률 보고 없이 바로 true 를 준다.
        let ready = await ExportSourceMaterialization.materialize(urls) { [weak self] progress in
            guard reportsGlobalStatus else { return }
            Task { @MainActor in
                self?.statusMessage = self?.text(
                    AppLocalizedPhrase.exportDownloadingSourcesFormat,
                    "\(progress.ready)",
                    "\(progress.total)"
                ) ?? ""
            }
        }
        if !ready, reportsGlobalStatus {
            statusMessage = text(AppLocalizedPhrase.exportSourceDownloadFailed)
        }
        return ready
    }

    func prepareCleanedRawForExport(_ frame: ScanFrame, format: ExportFormat) async -> Bool {
        let requiresCleanedRaw = format != .rawScanTIFF && frame.defectEdits.contains {
            $0.enabled && $0.strength > 1e-3
        }
        guard requiresCleanedRaw else { return true }

        // 같은 경로의 원본 바이트가 외부에서 바뀐 경우 helper가 stale cache를 폐기하고
        // 새 원본 기반 full rebuild를 시작한다. 그 복구 작업까지 기다린 뒤 export 입력을 판정한다.
        if !(await prepareCleanedRawForConsumption(frame)) {
            let sourceRecovery = frame.cleanRawTask
            await sourceRecovery?.value
        }

        let activeBuild = frame.cleanRawTask
        await activeBuild?.value
        if await cleanedRawIsUsableForExport(frame) { return true }

        discardCleanedRaw(frame, preservingDefectSidecar: true)
        rebuildCleanedRaw(frame)
        let rebuild = frame.cleanRawTask
        await rebuild?.value
        return await cleanedRawIsUsableForExport(frame)
    }

    private func cleanedRawIsUsableForExport(_ frame: ScanFrame) async -> Bool {
        guard await prepareCleanedRawForConsumption(frame),
              frame.cleanedRawEditCount == frame.defectEdits.count,
              let identity = frame.boundDefectRecipeIdentity else { return false }
        if frame.identityMatchedCleanedRawImage != nil { return true }
        guard let url = frame.identityMatchedCleanedRawDiskURL else { return false }
        let frameID = frame.id
        let expectedSourceIdentity = identity.sourceIdentity
        let rawURL = frame.rawScanURL
        let revision = frame.cleanRawRevision
        // 디코드 결과를 버리지 않고 메모리로 올린다. 예전에는 "읽히기는 하나"만 확인하고 버려서,
        // 곧바로 이어지는 내보내기가 같은 cleaned raw TIFF 를 처음부터 다시 디코드했다.
        let decoded = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard CleanedRawCacheFile.isOwnedCacheURL(url, frameID: frameID),
                  (try? AppModel.defectSourceIdentity(for: rawURL)) == expectedSourceIdentity else {
                return nil
            }
            return decodeCleanedRaw(url)
        }.value
        guard let decoded else { return false }
        // 대기 중 프레임 상태가 움직였으면 판정만 유지하고 픽셀은 올리지 않는다.
        guard ownsFrame(frame),
              frame.rawScanURL == rawURL,
              frame.cleanRawRevision == revision,
              frame.defectRecipeIdentity == identity,
              frame.cleanedRawDiskIdentity == identity else { return true }
        frame.cleanedRawImage = decoded
        frame.cleanedRawMemoryIdentity = identity
        frame.cleanedRawEditCount = frame.defectEdits.count
        frame.cleanedRawAppliedStamps = frame.defectEdits.map(\.appliedStamp)
        cleanedRawResidentInsert(frame)
        return true
    }
}
