import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

extension ScanSession {
    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ScanWorkflowValidationError.invariantViolation(
                "지원하지 않는 ScanSession schemaVersion: \(schemaVersion)"
            )
        }
        guard createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ScanWorkflowValidationError.invalidValue("session.createdAt이 유효하지 않습니다")
        }
        try requireNonempty(device.id, field: "session.device.id")
        try requireNonempty(device.displayName, field: "session.device.displayName")
        try requireNonempty(device.vendor, field: "session.device.vendor")
        try requireNonempty(device.model, field: "session.device.model")
        guard device.backendType == backend.type else {
            throw ScanWorkflowValidationError.invariantViolation(
                "장치와 백엔드 스냅샷의 BackendType이 서로 다릅니다"
            )
        }
        try backend.validate()
        try environment.validate()
        if backend.type == .plugin {
            guard let pluginIdentifier = backend.pluginIdentifier else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "plugin 세션에 pluginIdentifier가 없습니다"
                )
            }
            let prefix = "plugin:\(pluginIdentifier):"
            guard device.id.hasPrefix(prefix), device.id.count > prefix.count else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "세션 장치 ID가 backend pluginIdentifier namespace와 다릅니다"
                )
            }
        }

        if let closedAt {
            guard closedAt.timeIntervalSinceReferenceDate.isFinite, closedAt >= createdAt else {
                throw ScanWorkflowValidationError.invalidValue(
                    "session.closedAt은 createdAt보다 빠를 수 없습니다"
                )
            }
        }

        var jobIDs = Set<UUID>()
        var ordinals = Set<Int>()
        var pathOwners: [String: UUID] = [:]
        var fileObjectOwners: [CaptureFileObjectKey: UUID] = [:]
        var publicationFrameIDs = Set<UUID>()
        var publicationScanIndices = Set<Int>()
        var runningCount = 0
        var hasUnresolvedHardwarePredecessor = false
        var hasPendingFinalizationPredecessor = false

        func claimPath(_ url: URL, jobID: UUID, field: String) throws {
            let key = url.standardizedFileURL.path
            if let owner = pathOwners[key], owner != jobID {
                throw ScanWorkflowValidationError.invariantViolation(
                    "서로 다른 ScanJob이 같은 \(field) 경로를 소유할 수 없습니다"
                )
            }
            pathOwners[key] = jobID
        }

        func claimObservation(
            _ observation: CaptureFileObservation,
            jobID: UUID,
            field: String
        ) throws {
            let key = CaptureFileObjectKey(
                device: observation.device,
                inode: observation.inode
            )
            if let owner = fileObjectOwners[key], owner != jobID {
                throw ScanWorkflowValidationError.invariantViolation(
                    "서로 다른 ScanJob이 같은 \(field) 파일 개체를 소유할 수 없습니다"
                )
            }
            fileObjectOwners[key] = jobID
        }

        for (index, job) in jobs.enumerated() {
            guard jobIDs.insert(job.id).inserted else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "ScanSession에 중복 job UUID가 있습니다: \(job.id)"
                )
            }
            guard ordinals.insert(job.ordinal).inserted else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "ScanSession에 중복 job ordinal이 있습니다: \(job.ordinal)"
                )
            }
            guard job.ordinal == index + 1 else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "ScanSession 작업 배열은 1부터 연속된 ordinal 순서여야 합니다"
                )
            }
            guard job.sessionID == id else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "ScanJob의 sessionID가 소유 ScanSession과 다릅니다"
                )
            }
            guard job.requestedOptions.scannerID == device.id else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "ScanJob의 scannerID가 세션 장치와 다릅니다"
                )
            }
            guard job.createdAt >= createdAt else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "ScanJob 생성 시각이 세션 생성 시각보다 빠릅니다"
                )
            }
            try job.validate()

            if let publication = job.framePublication {
                guard publicationFrameIDs.insert(publication.frameID).inserted else {
                    throw ScanWorkflowValidationError.invariantViolation(
                        "ScanSession의 full 작업들이 같은 publish frame UUID를 예약할 수 없습니다"
                    )
                }
                guard publicationScanIndices.insert(publication.scanIndex).inserted else {
                    throw ScanWorkflowValidationError.invariantViolation(
                        "ScanSession의 full 작업들이 같은 scanIndex를 예약할 수 없습니다"
                    )
                }
            }

            guard let requestedOutputURL = job.requestedOptions.temporaryOutputURL else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "모든 ScanJob에는 job 전용 temporaryOutputURL이 필요합니다"
                )
            }
            try claimPath(
                requestedOutputURL,
                jobID: job.id,
                field: "requested output"
            )

            if job.state == .running {
                runningCount += 1
                guard runningCount == 1 else {
                    throw ScanWorkflowValidationError.invariantViolation(
                        "한 ScanSession에서 동시에 running인 하드웨어 작업은 하나만 허용됩니다"
                    )
                }
            }
            if job.startedAt != nil, hasUnresolvedHardwarePredecessor {
                throw ScanWorkflowValidationError.invariantViolation(
                    "앞선 queued/running 작업을 건너뛰고 뒤 작업을 시작할 수 없습니다"
                )
            }
            if job.state == .succeeded, hasPendingFinalizationPredecessor {
                throw ScanWorkflowValidationError.invariantViolation(
                    "앞선 pending finalization을 건너뛰고 뒤 manifest를 성공 처리할 수 없습니다"
                )
            }

            if let pendingCapture = job.pendingCapture {
                guard pendingCapture.result.backendUsed == backend.type else {
                    throw ScanWorkflowValidationError.invariantViolation(
                        "pendingCapture의 백엔드가 세션 스냅샷과 다릅니다"
                    )
                }
                try claimPath(
                    pendingCapture.rawFileURL,
                    jobID: job.id,
                    field: "pending RGB"
                )
                try claimObservation(
                    pendingCapture.rawObservation,
                    jobID: job.id,
                    field: "pending RGB"
                )
                if let infraredFileURL = pendingCapture.infraredFileURL,
                   let infraredObservation = pendingCapture.infraredObservation {
                    try claimPath(
                        infraredFileURL,
                        jobID: job.id,
                        field: "pending IR"
                    )
                    try claimObservation(
                        infraredObservation,
                        jobID: job.id,
                        field: "pending IR"
                    )
                }
            }
            if let manifest = job.captureManifest {
                guard manifest.result.backendUsed == backend.type else {
                    throw ScanWorkflowValidationError.invariantViolation(
                        "CaptureManifest의 백엔드가 세션 스냅샷과 다릅니다"
                    )
                }
                if case .verified(let options) = manifest.appliedOptionsEvidence,
                   options.scannerID != device.id {
                    throw ScanWorkflowValidationError.invariantViolation(
                        "CaptureManifest의 검증된 장치가 세션 스냅샷과 다릅니다"
                    )
                }
                try claimPath(manifest.rgbFile.originalURL, jobID: job.id, field: "manifest RGB")
                try claimObservation(
                    manifest.rgbObservation,
                    jobID: job.id,
                    field: "manifest RGB"
                )
                if let infraredFile = manifest.infraredFile,
                   let infraredObservation = manifest.infraredObservation {
                    try claimPath(
                        infraredFile.originalURL,
                        jobID: job.id,
                        field: "manifest IR"
                    )
                    try claimObservation(
                        infraredObservation,
                        jobID: job.id,
                        field: "manifest IR"
                    )
                }
            }
            if let closedAt, job.updatedAt > closedAt {
                throw ScanWorkflowValidationError.invariantViolation(
                    "ScanJob 갱신 시각이 세션 종료 시각보다 늦습니다"
                )
            }

            if job.state == .queued || job.state == .running {
                hasUnresolvedHardwarePredecessor = true
            }
            if job.state == .finalizing || (job.state == .failed && job.pendingCapture != nil) {
                hasPendingFinalizationPredecessor = true
            }
        }

        if closedAt != nil,
           jobs.contains(where: {
               $0.state == .queued
                   || $0.state == .running
                   || $0.state == .finalizing
                   || $0.pendingCapture != nil
           }) {
            throw ScanWorkflowValidationError.invariantViolation(
                "진행 가능한 작업이 남은 ScanSession은 닫을 수 없습니다"
            )
        }
    }

}
