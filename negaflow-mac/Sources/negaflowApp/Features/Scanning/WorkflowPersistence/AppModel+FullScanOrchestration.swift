import AppKit
import Chromabase
import Foundation
import ScannerKit

struct FullScanPlan {
    let session: ScanSession
    let assignment: LibraryScanRollAssignment
}

struct FullScanPublicationState {
    var canPublishNextManifest = true
    var publishedFrameCount = 0
    var stopReason: ScannerError?
    var unrecordedOrdinals: [Int] = []
}

extension AppModel {

    /// 본스캔은 하드웨어 호출보다 먼저 queued generation을 기록하고, receipt가 기록된
    /// finalizing 작업만 백그라운드 fixity 계산에 넘긴다.
    func scanFullFrames(
        count: Int,
        scannerID: String,
        backend: ScannerBackend,
        capabilities: ScannerCapabilities,
        sessionID: UUID,
        previewCarryover: PreviewScanCarryover?,
        flatbedRegions: [FlatbedScanRegion],
        flatbedPreviewScanArea: ScanArea?
    ) async {
        let plan: FullScanPlan
        do {
            plan = try await makeFullScanPlan(
                count: count,
                scannerID: scannerID,
                backend: backend,
                capabilities: capabilities,
                sessionID: sessionID,
                previewCarryover: previewCarryover,
                flatbedRegions: flatbedRegions,
                flatbedPreviewScanArea: flatbedPreviewScanArea
            )
        } catch {
            finishFullScanPreparationFailure(error, sessionID: sessionID)
            return
        }

        guard activeScanSessionID == sessionID else { return }
        let initialSessions = scanSessions + [plan.session]
        let initialAssignments = scanRollAssignments + [plan.assignment]
        guard publishScanGeneration(
            frames: frames,
            rolls: rolls,
            activeRollID: activeRollID,
            sessions: initialSessions,
            assignments: initialAssignments
        ) else {
            finishFullScanPreparationFailure(
                ScannerError(.ioFailure, text(AppLocalizedPhrase.scanWorkflowPersistenceFailed)),
                sessionID: sessionID
            )
            return
        }

        var publicationTask: Task<FullScanPublicationState, Never>?
        var hardwareFailed = false

        for ordinal in 1...count {
            batchIndex = ordinal - 1
            scanFraction = 0
            guard activeScanSessionID == sessionID else { break }
            guard let currentSession = scanSessions.first(where: { $0.id == sessionID }),
                  let queuedJob = currentSession.jobs.first(where: { $0.ordinal == ordinal }) else {
                hardwareFailed = true
                setScanWorkflowError(
                    ScannerError(.ioFailure, text(AppLocalizedPhrase.scanWorkflowInvalidState)),
                    frameNumber: ordinal
                )
                break
            }

            let runningJob: ScanJob
            let runningSession: ScanSession
            do {
                runningJob = try queuedJob.started(at: max(Date(), queuedJob.updatedAt))
                runningSession = try currentSession.replacing(runningJob)
            } catch {
                hardwareFailed = true
                setScanWorkflowError(error, frameNumber: ordinal)
                break
            }
            guard replaceAndPublishScanSession(runningSession) else {
                hardwareFailed = true
                setScanWorkflowError(
                    ScannerError(.ioFailure, text(AppLocalizedPhrase.scanWorkflowPersistenceFailed)),
                    frameNumber: ordinal
                )
                break
            }

            scanPhase = .scanningRGB
            statusMessage = text(AppLocalizedPhrase.filmScanPreparing)
            let captureStartedAt = runningJob.startedAt ?? runningJob.updatedAt
            do {
                let requestedOptions = runningJob.requestedOptions
                let result = try await Task.detached(priority: .userInitiated) {
                    try await backend.startFullScan(
                        requestedOptions,
                        progress: { [weak self] progress in
                            Task { @MainActor in
                                self?.update(progress, sessionID: sessionID)
                            }
                        }
                    )
                }.value
                let flatbedRegion = flatbedRegions.indices.contains(ordinal - 1)
                    ? flatbedRegions[ordinal - 1]
                    : nil
                // 백엔드는 요청 영역을 그대로 쓰지 못할 수 있다. 결과 픽셀은 요청이 아니라
                // 실제로 적용된 영역과 대조해야 한다(프리뷰 경로와 같은 기준).
                let verifiedScanArea: ScanArea?
                switch result.appliedOptionsEvidence {
                case .verified(let appliedOptions): verifiedScanArea = appliedOptions.scanArea
                case .unknownLegacy: verifiedScanArea = nil
                }
                let comparisonScanArea = verifiedScanArea ?? requestedOptions.scanArea
                if flatbedRegion?.source == .automatic,
                   !FlatbedScanRegionGeometry.outputMatchesPhysicalAspect(
                       width: result.width,
                       height: result.height,
                       scanArea: comparisonScanArea,
                       relativeTolerance: 0.02,
                       minimumPixelTolerance: 3
                   ) {
                    Self.removeUncommittedScanOutput(
                        result.rawFileURL,
                        infraredURL: result.infraredFileURL,
                        requestedURL: requestedOptions.temporaryOutputURL
                    )
                    throw ScannerError(
                        .ioFailure,
                        text(AppLocalizedPhrase.flatbedGeometryMismatch)
                            + " "
                            + FlatbedScanRegionGeometry.outputAspectDiagnostic(
                                width: result.width,
                                height: result.height,
                                scanArea: comparisonScanArea,
                                requestedScanArea: requestedOptions.scanArea
                            )
                    )
                }
                guard activeScanSessionID == sessionID,
                      libraryLifecycleState == .idle || libraryLifecycleState == .ready else {
                    Self.removeUncommittedScanOutput(
                        result.rawFileURL,
                        infraredURL: result.infraredFileURL,
                        requestedURL: runningJob.requestedOptions.temporaryOutputURL
                    )
                    break
                }

                let captureCompletedAt = max(Date(), captureStartedAt)
                let pendingCapture = try PendingCaptureSnapshot(
                    scanResult: result,
                    captureStartedAt: captureStartedAt,
                    captureCompletedAt: captureCompletedAt
                )
                guard let latestSession = scanSessions.first(where: { $0.id == sessionID }),
                      let latestRunningJob = latestSession.jobs.first(where: {
                          $0.id == runningJob.id && $0.state == .running
                      }) else {
                    throw ScannerError(.ioFailure, text(AppLocalizedPhrase.scanWorkflowInvalidState))
                }
                let finalizingJob = try latestRunningJob.finalizing(
                    with: pendingCapture,
                    at: max(captureCompletedAt, latestRunningJob.updatedAt)
                )
                let finalizingSession = try latestSession.replacing(finalizingJob)
                guard replaceAndPublishScanSession(finalizingSession) else {
                    hardwareFailed = true
                    setScanWorkflowError(
                        ScannerError(.ioFailure, text(AppLocalizedPhrase.scanWorkflowPersistenceFailed)),
                        frameNumber: ordinal
                    )
                    break
                }

                scanFraction = 1
                let task = Task.detached(priority: .utility) {
                    try CaptureManifest.build(
                        sessionID: sessionID,
                        jobID: finalizingJob.id,
                        attempt: finalizingJob.attempt,
                        kind: finalizingJob.kind,
                        requestedOptions: finalizingJob.requestedOptions,
                        pendingCapture: pendingCapture
                    )
                }
                let previousPublicationTask = publicationTask
                publicationTask = Task { [weak self] in
                    var state = await previousPublicationTask?.value
                        ?? FullScanPublicationState()
                    guard let self else { return state }
                    let manifest: CaptureManifest
                    do {
                        manifest = try await task.value
                    } catch {
                        let scannerError = self.scannerError(from: error)
                        let recorded = self.failFinalization(
                            sessionID: sessionID,
                            jobID: finalizingJob.id,
                            error: scannerError
                        )
                        if state.canPublishNextManifest {
                            state.canPublishNextManifest = false
                            state.stopReason = scannerError
                            self.setScanWorkflowError(
                                scannerError,
                                frameNumber: self.scanOrdinal(
                                    sessionID: sessionID,
                                    jobID: finalizingJob.id
                                )
                            )
                        } else if !recorded {
                            state.unrecordedOrdinals.append(self.scanOrdinal(
                                sessionID: sessionID,
                                jobID: finalizingJob.id
                            ))
                        }
                        return state
                    }

                    guard state.canPublishNextManifest else {
                        if let stopReason = state.stopReason,
                           !self.failFinalization(
                               sessionID: sessionID,
                               jobID: finalizingJob.id,
                               error: stopReason
                           ) {
                            state.unrecordedOrdinals.append(self.scanOrdinal(
                                sessionID: sessionID,
                                jobID: finalizingJob.id
                            ))
                        }
                        return state
                    }

                    switch self.publishFinalizedScan(
                        manifest,
                        sessionID: sessionID,
                        jobID: finalizingJob.id
                    ) {
                    case .success:
                        state.publishedFrameCount += 1
                    case .failure(let publishError):
                        state.canPublishNextManifest = false
                        state.stopReason = publishError
                        if !self.failFinalization(
                            sessionID: sessionID,
                            jobID: finalizingJob.id,
                            error: publishError
                        ) {
                            state.unrecordedOrdinals.append(self.scanOrdinal(
                                sessionID: sessionID,
                                jobID: finalizingJob.id
                            ))
                        }
                        self.setScanWorkflowError(
                            publishError,
                            frameNumber: self.scanOrdinal(
                                sessionID: sessionID,
                                jobID: finalizingJob.id
                            )
                        )
                    }
                    return state
                }
            } catch {
                guard activeScanSessionID == sessionID else { break }
                let scannerError = scannerError(from: error)
                hardwareFailed = true
                if !failHardwareJobAndCancelQueued(
                    sessionID: sessionID,
                    jobID: runningJob.id,
                    error: scannerError
                ) {
                    setScanWorkflowError(
                        ScannerError(.ioFailure, text(AppLocalizedPhrase.scanWorkflowPersistenceFailed)),
                        frameNumber: ordinal
                    )
                } else {
                    setScanWorkflowError(scannerError, frameNumber: ordinal)
                }
                break
            }
        }

        if activeScanSessionID == sessionID,
           hardwareFailed,
           let session = scanSessions.first(where: { $0.id == sessionID }) {
            _ = cancelQueuedJobs(in: session)
        }

        if activeScanSessionID != sessionID, publicationTask != nil {
            isScanFinalizationInProgress = true
        }

        // manifest 계산은 다음 하드웨어 스캔과 겹치지만, 발행은 ordinal 순서의 task chain으로
        // 이어진다. 따라서 RGB/IR 파일이 모두 준비된 첫 프레임부터 즉시 보이면서도 앞 프레임
        // 실패 뒤의 프레임을 잘못 발행하지 않는다.
        let publicationState = await publicationTask?.value ?? FullScanPublicationState()
        let canPublishNextManifest = publicationState.canPublishNextManifest
        let publishedFrameCount = publicationState.publishedFrameCount
        let unrecordedOrdinals = publicationState.unrecordedOrdinals
        if let firstUnrecorded = unrecordedOrdinals.first {
            setScanWorkflowError(
                ScannerError(.ioFailure, text(AppLocalizedPhrase.scanWorkflowPersistenceFailed)),
                frameNumber: firstUnrecorded
            )
        }

        _ = closeScanSessionIfTerminal(sessionID)
        isScanFinalizationInProgress = false
        if publishedFrameCount > 0 {
            if flatbedRegions.isEmpty || publishedFrameCount == count {
                removeEphemeralPreviewFrames(keeping: nil)
            } else if let session = scanSessions.first(where: { $0.id == sessionID }) {
                let succeededOrdinals = Set(
                    session.jobs.filter { $0.state == .succeeded }.map(\.ordinal)
                )
                flatbedScanRegions = flatbedRegions.enumerated().compactMap { offset, region in
                    succeededOrdinals.contains(offset + 1) ? nil : region
                }
                selectedFlatbedScanRegionID = flatbedScanRegions.first?.id
                if let flatbedPreviewFrameID { selectedFrameID = flatbedPreviewFrameID }
            }
        }

        guard activeScanSessionID == sessionID else { return }
        activeScanSessionID = nil
        activeScannerBackend = nil
        batchTotal = 0
        batchIndex = 0
        isScanning = false
        let session = scanSessions.first(where: { $0.id == sessionID })
        let succeededCount = session?.jobs.count(where: { $0.state == .succeeded }) ?? 0
        if succeededCount == count, !hardwareFailed, canPublishNextManifest {
            scanPhase = .complete
            scanFraction = 1
            statusMessage = text(AppLocalizedPhrase.framesScanCompleteFormat, count)
        } else if scanPhase != .error {
            scanPhase = .error
        }
    }


}
