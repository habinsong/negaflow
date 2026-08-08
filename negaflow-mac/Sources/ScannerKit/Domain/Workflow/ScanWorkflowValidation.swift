import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

// MARK: - Validation helpers

protocol ScanWorkflowValidatable {
    func validate() throws
}

extension CaptureManifest: ScanWorkflowValidatable {}
extension ScanJob: ScanWorkflowValidatable {}
extension ScanSession: ScanWorkflowValidatable {}
extension ScanBackendSnapshot: ScanWorkflowValidatable {}
extension ScanEnvironmentSnapshot: ScanWorkflowValidatable {}
extension ScanFramePublicationSnapshot: ScanWorkflowValidatable {}
extension CaptureFileIdentity: ScanWorkflowValidatable {}
extension CaptureFileObservation: ScanWorkflowValidatable {}
extension CaptureResultSnapshot: ScanWorkflowValidatable {}
extension PendingCaptureSnapshot: ScanWorkflowValidatable {}

struct CaptureFileObjectKey: Hashable {
    let device: UInt64
    let inode: UInt64
}

func decodeValidated<T: ScanWorkflowValidatable>(_ value: T, decoder: Decoder) throws {
    do {
        try value.validate()
    } catch {
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "스캔 workflow 불변식 검증 실패: \(error.localizedDescription)",
                underlyingError: error
            )
        )
    }
}

func requireSupportedSchema<Key: CodingKey>(
    _ schemaVersion: Int,
    current: Int,
    record: String,
    key: Key,
    container: KeyedDecodingContainer<Key>
) throws {
    guard schemaVersion == current else {
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "지원하지 않는 \(record) schemaVersion: \(schemaVersion); 지원 버전: \(current)"
        )
    }
}

func validateOptions(_ options: ScanOptions, kind: ScanJobKind, field: String) throws {
    try requireNonempty(options.scannerID, field: "\(field).scannerID")
    guard options.resolution.dpi >= 0 else {
        throw ScanWorkflowValidationError.invalidValue("\(field).resolution은 음수일 수 없습니다")
    }
    switch kind {
    case .preview where options.resolution != .preview:
        throw ScanWorkflowValidationError.invariantViolation(
            "preview 작업은 Resolution.preview를 사용해야 합니다"
        )
    case .full where options.resolution == .preview:
        throw ScanWorkflowValidationError.invariantViolation(
            "full 작업은 Resolution.preview를 사용할 수 없습니다"
        )
    default:
        break
    }
    guard options.scanArea.originXMM.isFinite,
          options.scanArea.originYMM.isFinite,
          options.scanArea.originXMM >= 0,
          options.scanArea.originYMM >= 0,
          options.scanArea.widthMM.isFinite,
          options.scanArea.heightMM.isFinite,
          options.scanArea.widthMM > 0,
          options.scanArea.heightMM > 0 else {
        throw ScanWorkflowValidationError.invalidValue("\(field).scanArea가 유효하지 않습니다")
    }
    if let exposure = options.hardwareExposureTime, exposure < 0 {
        throw ScanWorkflowValidationError.invalidValue(
            "\(field).hardwareExposureTime은 음수일 수 없습니다"
        )
    }
    if let brightness = options.brightnessAdjustment, !brightness.isFinite {
        throw ScanWorkflowValidationError.invalidValue(
            "\(field).brightnessAdjustment가 유한값이 아닙니다"
        )
    }
    if let contrast = options.contrastAdjustment, !contrast.isFinite {
        throw ScanWorkflowValidationError.invalidValue(
            "\(field).contrastAdjustment가 유한값이 아닙니다"
        )
    }
    if let temporaryOutputURL = options.temporaryOutputURL, !temporaryOutputURL.isFileURL {
        throw ScanWorkflowValidationError.invalidValue(
            "\(field).temporaryOutputURL은 file URL이어야 합니다"
        )
    }
}

func validateResultKind(
    _ result: CaptureResultSnapshot,
    kind: ScanJobKind,
    field: String
) throws {
    switch kind {
    case .preview where result.resolution != .preview:
        throw ScanWorkflowValidationError.invariantViolation(
            "\(field)은 preview 작업에서 Resolution.preview여야 합니다"
        )
    case .full where result.resolution.dpi <= 0:
        throw ScanWorkflowValidationError.invariantViolation(
            "\(field)은 full 작업에서 1dpi 이상이어야 합니다"
        )
    default:
        break
    }
}

func validateEvidenceOwnership(
    _ evidence: AppliedScanOptionsEvidence,
    jobID: UUID,
    scannerID: String,
    kind: ScanJobKind,
    field: String
) throws {
    switch evidence {
    case .verified(let options):
        try validateOptions(options, kind: kind, field: field)
        guard options.requestID == jobID else {
            throw ScanWorkflowValidationError.invariantViolation(
                "\(field)의 requestID가 소유 ScanJob UUID와 다릅니다"
            )
        }
        guard options.scannerID == scannerID else {
            throw ScanWorkflowValidationError.invariantViolation(
                "\(field)의 scannerID가 요청 장치와 다릅니다"
            )
        }
    case .unknownLegacy(let protocolVersion):
        guard protocolVersion == ScannerPluginManifest.legacyProtocolVersion else {
            throw ScanWorkflowValidationError.invariantViolation(
                "\(field)의 legacy 확인 불가 상태는 protocol v1에만 유효합니다"
            )
        }
    }
}

func requireNonempty(_ value: String, field: String) throws {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ScanWorkflowValidationError.invalidValue("\(field)는 비어 있을 수 없습니다")
    }
}

func requireOptionalNonempty(_ value: String?, field: String) throws {
    if let value {
        try requireNonempty(value, field: field)
    }
}
