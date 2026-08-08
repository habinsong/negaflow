import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

extension ScanSession {
    public func appending(_ job: ScanJob) throws -> ScanSession {
        guard closedAt == nil else {
            throw ScanWorkflowValidationError.invariantViolation(
                "닫힌 ScanSession에는 작업을 추가할 수 없습니다"
            )
        }
        guard job.ordinal == jobs.count + 1 else {
            throw ScanWorkflowValidationError.invariantViolation(
                "추가하는 ScanJob ordinal은 현재 작업 수 다음 값이어야 합니다"
            )
        }
        guard job.state == .queued,
              job.attempt == 1,
              job.startedAt == nil,
              job.finishedAt == nil,
              job.pendingCapture == nil,
              job.captureManifest == nil,
              job.failure == nil else {
            throw ScanWorkflowValidationError.invariantViolation(
                "새 ScanJob은 payload가 없는 첫 번째 queued 시도여야 합니다"
            )
        }
        return try ScanSession(
            id: id,
            createdAt: createdAt,
            device: device,
            backend: backend,
            environment: environment,
            jobs: jobs + [job]
        )
    }

    /// 동일 UUID 작업의 새 값(예: 상태 전이 결과)만 교체한다.
    public func replacing(_ job: ScanJob) throws -> ScanSession {
        guard closedAt == nil else {
            throw ScanWorkflowValidationError.invariantViolation(
                "닫힌 ScanSession의 작업을 변경할 수 없습니다"
            )
        }
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else {
            throw ScanWorkflowValidationError.invariantViolation(
                "교체할 ScanJob UUID가 세션에 없습니다"
            )
        }
        let previous = jobs[index]
        guard job.sessionID == previous.sessionID,
              job.ordinal == previous.ordinal,
              job.kind == previous.kind,
              job.requestedOptions == previous.requestedOptions,
              job.framePublication == previous.framePublication,
              job.createdAt == previous.createdAt else {
            throw ScanWorkflowValidationError.invariantViolation(
                "ScanJob 교체 시 sessionID/ordinal/kind/requestedOptions/framePublication/createdAt은 변경할 수 없습니다"
            )
        }
        if job != previous {
            let expected = try previous.transitioned(
                to: job.state,
                at: job.updatedAt,
                pendingCapture: job.pendingCapture,
                manifest: job.captureManifest,
                failure: job.failure
            )
            guard expected == job else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "ScanJob 교체 값이 상태 전이 함수가 만든 값과 다릅니다"
                )
            }
        }
        var updatedJobs = jobs
        updatedJobs[index] = job
        return try ScanSession(
            id: id,
            createdAt: createdAt,
            device: device,
            backend: backend,
            environment: environment,
            jobs: updatedJobs
        )
    }

    public func closed(at timestamp: Date) throws -> ScanSession {
        guard closedAt == nil else {
            throw ScanWorkflowValidationError.invariantViolation("ScanSession이 이미 닫혀 있습니다")
        }
        return try ScanSession(
            id: id,
            createdAt: createdAt,
            closedAt: timestamp,
            device: device,
            backend: backend,
            environment: environment,
            jobs: jobs
        )
    }

}
