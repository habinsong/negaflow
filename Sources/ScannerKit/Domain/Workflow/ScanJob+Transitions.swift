import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

extension ScanJob {
    /// 상태 전이는 새 값을 반환하며 원래 작업 값은 변경하지 않는다.
    public func transitioned(
        to newState: ScanJobState,
        at timestamp: Date,
        pendingCapture: PendingCaptureSnapshot? = nil,
        manifest: CaptureManifest? = nil,
        failure: ScannerErrorSnapshot? = nil
    ) throws -> ScanJob {
        guard timestamp.timeIntervalSinceReferenceDate.isFinite, timestamp >= updatedAt else {
            throw ScanWorkflowValidationError.invalidValue(
                "작업 전이 시각은 현재 updatedAt보다 빠를 수 없습니다"
            )
        }
        guard Self.isLegalTransition(from: state, to: newState) else {
            throw ScanWorkflowValidationError.illegalTransition(from: state, to: newState)
        }

        let nextAttempt: Int
        let nextStartedAt: Date?
        let nextFinishedAt: Date?
        let nextPendingCapture: PendingCaptureSnapshot?
        switch newState {
        case .queued:
            guard self.pendingCapture == nil,
                  pendingCapture == nil,
                  manifest == nil,
                  failure == nil else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "pending finalization이 없는 실패/취소 작업만 하드웨어 재시도할 수 있습니다"
                )
            }
            let increment = attempt.addingReportingOverflow(1)
            guard !increment.overflow else {
                throw ScanWorkflowValidationError.invalidValue(
                    "job.attempt가 Int 범위를 초과해 재시도할 수 없습니다"
                )
            }
            nextAttempt = increment.partialValue
            nextStartedAt = nil
            nextFinishedAt = nil
            nextPendingCapture = nil
        case .running:
            guard pendingCapture == nil, manifest == nil, failure == nil else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "running 전이에는 결과 payload를 전달할 수 없습니다"
                )
            }
            nextAttempt = attempt
            nextStartedAt = timestamp
            nextFinishedAt = nil
            nextPendingCapture = nil
        case .finalizing:
            guard let pendingCapture,
                  manifest == nil,
                  failure == nil,
                  state != .failed || pendingCapture == self.pendingCapture else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "finalizing 전이에는 동일한 pendingCapture만 필요합니다"
                )
            }
            nextAttempt = attempt
            nextStartedAt = startedAt
            nextFinishedAt = nil
            nextPendingCapture = pendingCapture
        case .succeeded:
            guard pendingCapture == nil, manifest != nil, failure == nil else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "succeeded 전이에는 captureManifest만 필요합니다"
                )
            }
            guard let receipt = self.pendingCapture,
                  let manifest,
                  manifest.result == receipt.result,
                  manifest.appliedOptionsEvidence == receipt.appliedOptionsEvidence,
                  manifest.captureStartedAt == receipt.captureStartedAt,
                  manifest.captureCompletedAt == receipt.captureCompletedAt,
                  manifest.rgbObservation == receipt.rawObservation,
                  manifest.infraredObservation == receipt.infraredObservation,
                  manifest.rgbFile.originalURL.standardizedFileURL == receipt.rawFileURL.standardizedFileURL,
                  manifest.infraredFile?.originalURL.standardizedFileURL
                    == receipt.infraredFileURL?.standardizedFileURL else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "captureManifest가 finalizing receipt와 일치하지 않습니다"
                )
            }
            try manifest.verifyCurrentFiles()
            nextAttempt = attempt
            nextStartedAt = startedAt
            nextFinishedAt = timestamp
            nextPendingCapture = nil
        case .failed:
            guard manifest == nil, failure != nil else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "failed 전이에는 ScannerErrorSnapshot만 필요합니다"
                )
            }
            let preservedPendingCapture: PendingCaptureSnapshot?
            if state == .finalizing {
                guard self.pendingCapture != nil,
                      pendingCapture == nil || pendingCapture == self.pendingCapture else {
                    throw ScanWorkflowValidationError.invariantViolation(
                        "finalization 실패는 기존 pendingCapture를 그대로 보존해야 합니다"
                    )
                }
                preservedPendingCapture = self.pendingCapture
            } else {
                guard pendingCapture == nil else {
                    throw ScanWorkflowValidationError.invariantViolation(
                        "하드웨어 실행 실패에는 pendingCapture를 추가할 수 없습니다"
                    )
                }
                preservedPendingCapture = nil
            }
            nextAttempt = attempt
            nextStartedAt = startedAt
            nextFinishedAt = timestamp
            nextPendingCapture = preservedPendingCapture
        case .cancelled:
            guard pendingCapture == nil, manifest == nil, failure == nil else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "cancelled 전이에는 결과 payload를 전달할 수 없습니다"
                )
            }
            nextAttempt = attempt
            nextStartedAt = startedAt
            nextFinishedAt = timestamp
            nextPendingCapture = nil
        }

        return try ScanJob(
            id: id,
            sessionID: sessionID,
            ordinal: ordinal,
            attempt: nextAttempt,
            kind: kind,
            state: newState,
            requestedOptions: requestedOptions,
            framePublication: framePublication,
            createdAt: createdAt,
            updatedAt: timestamp,
            startedAt: nextStartedAt,
            finishedAt: nextFinishedAt,
            pendingCapture: nextPendingCapture,
            captureManifest: manifest,
            failure: failure
        )
    }

    public func started(at timestamp: Date) throws -> ScanJob {
        try transitioned(to: .running, at: timestamp)
    }

    public func finalizing(
        with pendingCapture: PendingCaptureSnapshot,
        at timestamp: Date
    ) throws -> ScanJob {
        try transitioned(to: .finalizing, at: timestamp, pendingCapture: pendingCapture)
    }

    public func succeeded(with manifest: CaptureManifest, at timestamp: Date) throws -> ScanJob {
        try transitioned(to: .succeeded, at: timestamp, manifest: manifest)
    }

    /// fixity/파일 검증 실패 뒤 같은 receipt와 attempt로 finalization만 다시 수행한다.
    public func retryFinalization(at timestamp: Date) throws -> ScanJob {
        guard let pendingCapture else {
            throw ScanWorkflowValidationError.invariantViolation(
                "재개할 pendingCapture가 없습니다"
            )
        }
        return try transitioned(
            to: .finalizing,
            at: timestamp,
            pendingCapture: pendingCapture
        )
    }

    public func failed(with error: ScannerError, at timestamp: Date) throws -> ScanJob {
        try transitioned(
            to: .failed,
            at: timestamp,
            failure: ScannerErrorSnapshot(error, recordedAt: timestamp)
        )
    }

    public func cancelled(at timestamp: Date) throws -> ScanJob {
        try transitioned(to: .cancelled, at: timestamp)
    }

    public func retried(at timestamp: Date) throws -> ScanJob {
        try transitioned(to: .queued, at: timestamp)
    }

}
