import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

extension ScanJob {
    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ScanWorkflowValidationError.invariantViolation(
                "지원하지 않는 ScanJob schemaVersion: \(schemaVersion)"
            )
        }
        guard ordinal > 0 else {
            throw ScanWorkflowValidationError.invalidValue("job.ordinal은 1 이상이어야 합니다")
        }
        guard attempt > 0 else {
            throw ScanWorkflowValidationError.invalidValue("job.attempt는 1 이상이어야 합니다")
        }
        try validateOptions(requestedOptions, kind: kind, field: "job.requestedOptions")
        switch kind {
        case .full:
            guard let framePublication else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "full ScanJob에는 framePublication 스냅샷이 필요합니다"
                )
            }
            try framePublication.validate()
        case .preview:
            guard framePublication == nil else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "preview ScanJob은 framePublication 스냅샷을 가질 수 없습니다"
                )
            }
        }
        guard requestedOptions.temporaryOutputURL != nil else {
            throw ScanWorkflowValidationError.invariantViolation(
                "모든 ScanJob에는 job 전용 temporaryOutputURL이 필요합니다"
            )
        }
        guard requestedOptions.requestID == id else {
            throw ScanWorkflowValidationError.invariantViolation(
                "ScanJob 요청 식별자가 job UUID와 다릅니다"
            )
        }
        guard createdAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt >= createdAt else {
            throw ScanWorkflowValidationError.invalidValue(
                "job.updatedAt은 createdAt보다 빠를 수 없습니다"
            )
        }
        if let startedAt {
            guard startedAt.timeIntervalSinceReferenceDate.isFinite,
                  startedAt >= createdAt,
                  startedAt <= updatedAt else {
                throw ScanWorkflowValidationError.invalidValue("job.startedAt 시간 범위가 잘못되었습니다")
            }
        }
        if let finishedAt {
            guard finishedAt.timeIntervalSinceReferenceDate.isFinite,
                  finishedAt >= (startedAt ?? createdAt),
                  finishedAt == updatedAt else {
                throw ScanWorkflowValidationError.invalidValue("job.finishedAt 시간 범위가 잘못되었습니다")
            }
        }

        switch state {
        case .queued:
            guard startedAt == nil, finishedAt == nil, pendingCapture == nil,
                  captureManifest == nil, failure == nil else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "queued 작업에는 시작/종료 시각 또는 결과 payload가 있을 수 없습니다"
                )
            }
        case .running:
            guard startedAt != nil, finishedAt == nil, pendingCapture == nil,
                  captureManifest == nil, failure == nil else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "running 작업은 startedAt만 가져야 합니다"
                )
            }
        case .finalizing:
            guard startedAt != nil, finishedAt == nil, pendingCapture != nil,
                  captureManifest == nil, failure == nil else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "finalizing 작업에는 pendingCapture와 startedAt이 필요합니다"
                )
            }
        case .succeeded:
            guard startedAt != nil, finishedAt != nil, pendingCapture == nil,
                  captureManifest != nil, failure == nil else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "succeeded 작업에는 captureManifest와 완료 시각이 필요합니다"
                )
            }
        case .failed:
            guard startedAt != nil, finishedAt != nil,
                  captureManifest == nil, failure != nil else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "failed 작업에는 ScannerErrorSnapshot과 완료 시각이 필요합니다"
                )
            }
        case .cancelled:
            guard finishedAt != nil, pendingCapture == nil,
                  captureManifest == nil, failure == nil else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "cancelled 작업에는 완료 시각만 필요합니다"
                )
            }
        }

        if let pendingCapture {
            try pendingCapture.validate()
            try validateResultKind(
                pendingCapture.result,
                kind: kind,
                field: "job.pendingCapture.result"
            )
            guard pendingCapture.captureStartedAt >= (startedAt ?? createdAt),
                  pendingCapture.captureCompletedAt <= updatedAt else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "pendingCapture 캡처 시각이 job 실행 구간을 벗어났습니다"
                )
            }
            try validateEvidenceOwnership(
                pendingCapture.appliedOptionsEvidence,
                jobID: id,
                scannerID: requestedOptions.scannerID,
                kind: kind,
                field: "job.pendingCapture.appliedOptionsEvidence"
            )
        }

        if let captureManifest {
            try captureManifest.validate()
            guard captureManifest.sessionID == sessionID,
                  captureManifest.jobID == id,
                  captureManifest.attempt == attempt,
                  captureManifest.kind == kind,
                  captureManifest.requestedOptions == requestedOptions else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "captureManifest가 소유 job/session/attempt/request와 일치하지 않습니다"
                )
            }
            guard let startedAt,
                  let finishedAt,
                  captureManifest.captureStartedAt >= startedAt,
                  captureManifest.captureCompletedAt <= finishedAt else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "manifest 캡처 시각이 job 실행 구간을 벗어났습니다"
                )
            }
        }
        if let failure, let startedAt, let finishedAt {
            guard failure.recordedAt.timeIntervalSinceReferenceDate.isFinite,
                  failure.recordedAt >= startedAt,
                  failure.recordedAt <= finishedAt else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "오류 기록 시각이 job 실행 구간을 벗어났습니다"
                )
            }
        }
    }

    static func isLegalTransition(from: ScanJobState, to: ScanJobState) -> Bool {
        switch (from, to) {
        case (.queued, .running),
             (.queued, .cancelled),
             (.running, .finalizing),
             (.running, .failed),
             (.running, .cancelled),
             (.finalizing, .succeeded),
             (.finalizing, .failed),
             (.failed, .queued),
             (.failed, .finalizing),
             (.cancelled, .queued):
            return true
        default:
            return false
        }
    }

}
