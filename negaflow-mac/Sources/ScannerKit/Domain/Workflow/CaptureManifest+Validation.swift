import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

extension CaptureManifest {
    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ScanWorkflowValidationError.invariantViolation(
                "지원하지 않는 CaptureManifest schemaVersion: \(schemaVersion)"
            )
        }
        guard attempt > 0 else {
            throw ScanWorkflowValidationError.invalidValue("manifest.attempt는 1 이상이어야 합니다")
        }
        try validateOptions(requestedOptions, kind: kind, field: "manifest.requestedOptions")
        guard requestedOptions.requestID == jobID else {
            throw ScanWorkflowValidationError.invariantViolation(
                "manifest 요청 식별자가 소유 ScanJob UUID와 다릅니다"
            )
        }
        try result.validate()
        try validateResultKind(result, kind: kind, field: "manifest.result")
        switch appliedOptionsEvidence {
        case .verified(let options):
            try validateOptions(options, kind: kind, field: "manifest.appliedOptions")
            guard options.requestID == jobID else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "검증된 적용 옵션의 요청 식별자가 소유 ScanJob UUID와 다릅니다"
                )
            }
            guard requestedOptions.scannerID == options.scannerID else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "요청/적용 scannerID가 서로 다릅니다"
                )
            }
            guard result.resolution == options.resolution,
                  result.bitDepth == options.bitDepth,
                  result.reportedResolution == options.resolution,
                  result.reportedBitDepth == options.bitDepth,
                  options.infraredEnabled == result.hasInfraredChannel else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "캡처 결과/reported provenance와 검증된 적용 옵션이 서로 다릅니다"
                )
            }
            guard options.temporaryOutputURL?.standardizedFileURL == rgbFile.originalURL.standardizedFileURL else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "검증된 적용 옵션의 출력 경로와 RGB fixity 경로가 다릅니다"
                )
            }
        case .unknownLegacy(let protocolVersion):
            guard protocolVersion == ScannerPluginManifest.legacyProtocolVersion,
                  result.backendUsed == .plugin else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "legacy 적용 옵션 확인 불가 상태는 plugin protocol v1에만 유효합니다"
                )
            }
        }
        guard captureStartedAt.timeIntervalSinceReferenceDate.isFinite,
              captureCompletedAt.timeIntervalSinceReferenceDate.isFinite,
              captureCompletedAt >= captureStartedAt else {
            throw ScanWorkflowValidationError.invalidValue(
                "captureCompletedAt은 captureStartedAt보다 빠를 수 없습니다"
            )
        }
        try rgbFile.validate()
        try infraredFile?.validate()
        guard result.hasInfraredChannel == (infraredFile != nil) else {
            throw ScanWorkflowValidationError.invariantViolation(
                "IR 결과 플래그와 infraredFile identity가 서로 다릅니다"
            )
        }
        try rgbObservation.validate()
        guard rgbObservation.originalURL.standardizedFileURL
                == rgbFile.originalURL.standardizedFileURL,
              rgbObservation.byteCount == rgbFile.byteCount else {
            throw ScanWorkflowValidationError.invariantViolation(
                "RGB fixity와 캡처 완료 관찰값이 서로 다릅니다"
            )
        }
        guard (infraredFile != nil) == (infraredObservation != nil) else {
            throw ScanWorkflowValidationError.invariantViolation(
                "IR fixity와 캡처 완료 관찰값 존재 여부가 다릅니다"
            )
        }
        if let infraredFile, let infraredObservation {
            try infraredObservation.validate()
            guard rgbFile.originalURL.standardizedFileURL
                    != infraredFile.originalURL.standardizedFileURL,
                  infraredObservation.originalURL.standardizedFileURL
                    == infraredFile.originalURL.standardizedFileURL,
                  infraredObservation.byteCount == infraredFile.byteCount,
                  rgbObservation.device != infraredObservation.device
                    || rgbObservation.inode != infraredObservation.inode else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "RGB와 IR fixity/관찰값은 서로 다른 파일을 정확히 가리켜야 합니다"
                )
            }
        }
    }

    public func verifyCurrentFiles() throws {
        try rgbObservation.verifyCurrentFile()
        try infraredObservation?.verifyCurrentFile()
        try rgbObservation.verifyCurrentFile()
    }

}
