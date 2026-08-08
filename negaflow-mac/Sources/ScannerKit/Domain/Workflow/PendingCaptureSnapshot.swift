import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

// MARK: - Pending capture receipt

/// 백엔드 캡처는 끝났지만 RGB/IR fixity와 manifest 생성이 끝나지 않은 상태를 보존한다.
/// 이 값이 있으면 앱 재시작 뒤 하드웨어를 다시 움직이지 않고 파일 검증만 재개할 수 있다.
public struct PendingCaptureSnapshot: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public let result: CaptureResultSnapshot
    public let appliedOptionsEvidence: AppliedScanOptionsEvidence
    public let captureStartedAt: Date
    public let captureCompletedAt: Date
    public let rawFileURL: URL
    public let infraredFileURL: URL?
    public let rawObservation: CaptureFileObservation
    public let infraredObservation: CaptureFileObservation?

    public init(
        result: CaptureResultSnapshot,
        appliedOptionsEvidence: AppliedScanOptionsEvidence,
        captureStartedAt: Date,
        captureCompletedAt: Date,
        rawFileURL: URL,
        infraredFileURL: URL? = nil,
        rawObservation: CaptureFileObservation? = nil,
        infraredObservation: CaptureFileObservation? = nil
    ) throws {
        let resolvedRawObservation: CaptureFileObservation
        if let rawObservation {
            resolvedRawObservation = rawObservation
        } else {
            resolvedRawObservation = try CaptureFileObservation.capture(for: rawFileURL)
        }
        let resolvedInfraredObservation: CaptureFileObservation?
        if let infraredObservation {
            resolvedInfraredObservation = infraredObservation
        } else if let infraredFileURL {
            resolvedInfraredObservation = try CaptureFileObservation.capture(for: infraredFileURL)
        } else {
            resolvedInfraredObservation = nil
        }
        self.schemaVersion = Self.currentSchemaVersion
        self.result = result
        self.appliedOptionsEvidence = appliedOptionsEvidence
        self.captureStartedAt = captureStartedAt
        self.captureCompletedAt = captureCompletedAt
        self.rawFileURL = rawFileURL
        self.infraredFileURL = infraredFileURL
        self.rawObservation = resolvedRawObservation
        self.infraredObservation = resolvedInfraredObservation
        try validate()
        try verifyCurrentFiles()
    }

    public init(
        scanResult: ScanResult,
        captureStartedAt: Date,
        captureCompletedAt: Date
    ) throws {
        try self.init(
            result: CaptureResultSnapshot(scanResult),
            appliedOptionsEvidence: scanResult.appliedOptionsEvidence,
            captureStartedAt: captureStartedAt,
            captureCompletedAt: captureCompletedAt,
            rawFileURL: scanResult.rawFileURL,
            infraredFileURL: scanResult.infraredFileURL
        )
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ScanWorkflowValidationError.invariantViolation(
                "지원하지 않는 PendingCaptureSnapshot schemaVersion: \(schemaVersion)"
            )
        }
        try result.validate()
        guard captureStartedAt.timeIntervalSinceReferenceDate.isFinite,
              captureCompletedAt.timeIntervalSinceReferenceDate.isFinite,
              captureCompletedAt >= captureStartedAt else {
            throw ScanWorkflowValidationError.invalidValue(
                "pendingCapture.captureCompletedAt은 captureStartedAt보다 빠를 수 없습니다"
            )
        }
        guard rawFileURL.isFileURL else {
            throw ScanWorkflowValidationError.invalidValue(
                "pendingCapture.rawFileURL은 file URL이어야 합니다"
            )
        }
        if let infraredFileURL {
            guard infraredFileURL.isFileURL,
                  infraredFileURL.standardizedFileURL != rawFileURL.standardizedFileURL else {
                throw ScanWorkflowValidationError.invalidValue(
                    "pendingCapture.infraredFileURL은 RGB와 다른 file URL이어야 합니다"
                )
            }
        }
        guard result.hasInfraredChannel == (infraredFileURL != nil) else {
            throw ScanWorkflowValidationError.invariantViolation(
                "pendingCapture IR 결과 플래그와 파일 경로가 서로 다릅니다"
            )
        }
        try rawObservation.validate()
        guard rawObservation.originalURL.standardizedFileURL == rawFileURL.standardizedFileURL else {
            throw ScanWorkflowValidationError.invariantViolation(
                "pendingCapture RGB 관찰 경로와 원본 경로가 다릅니다"
            )
        }
        guard (infraredFileURL != nil) == (infraredObservation != nil) else {
            throw ScanWorkflowValidationError.invariantViolation(
                "pendingCapture IR 경로와 관찰값 존재 여부가 다릅니다"
            )
        }
        if let infraredFileURL, let infraredObservation {
            try infraredObservation.validate()
            guard infraredObservation.originalURL.standardizedFileURL
                    == infraredFileURL.standardizedFileURL else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "pendingCapture IR 관찰 경로와 원본 경로가 다릅니다"
                )
            }
            guard rawObservation.device != infraredObservation.device
                    || rawObservation.inode != infraredObservation.inode else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "pendingCapture RGB와 IR은 서로 다른 파일이어야 합니다"
                )
            }
        }
        switch appliedOptionsEvidence {
        case .verified(let options):
            guard options.requestID != nil else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "검증된 적용 옵션에는 requestID가 필요합니다"
                )
            }
            guard options.resolution == result.resolution,
                  options.bitDepth == result.bitDepth,
                  result.reportedResolution == options.resolution,
                  result.reportedBitDepth == options.bitDepth,
                  options.infraredEnabled == result.hasInfraredChannel else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "검증된 적용 옵션과 캡처 결과/reported provenance가 서로 다릅니다"
                )
            }
            guard options.temporaryOutputURL?.standardizedFileURL == rawFileURL.standardizedFileURL else {
                throw ScanWorkflowValidationError.invariantViolation(
                    "검증된 적용 옵션의 출력 경로와 캡처 원본 경로가 다릅니다"
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
    }

    public func verifyCurrentFiles() throws {
        try rawObservation.verifyCurrentFile()
        try infraredObservation?.verifyCurrentFile()
        try rawObservation.verifyCurrentFile()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case result
        case appliedOptionsEvidence
        case captureStartedAt
        case captureCompletedAt
        case rawFileURL
        case infraredFileURL
        case rawObservation
        case infraredObservation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try requireSupportedSchema(
            schemaVersion,
            current: Self.currentSchemaVersion,
            record: "PendingCaptureSnapshot",
            key: .schemaVersion,
            container: container
        )
        self.schemaVersion = schemaVersion
        self.result = try container.decode(CaptureResultSnapshot.self, forKey: .result)
        self.appliedOptionsEvidence = try container.decode(
            AppliedScanOptionsEvidence.self,
            forKey: .appliedOptionsEvidence
        )
        self.captureStartedAt = try container.decode(Date.self, forKey: .captureStartedAt)
        self.captureCompletedAt = try container.decode(Date.self, forKey: .captureCompletedAt)
        self.rawFileURL = try container.decode(URL.self, forKey: .rawFileURL)
        self.infraredFileURL = try container.decodeIfPresent(URL.self, forKey: .infraredFileURL)
        self.rawObservation = try container.decode(
            CaptureFileObservation.self,
            forKey: .rawObservation
        )
        self.infraredObservation = try container.decodeIfPresent(
            CaptureFileObservation.self,
            forKey: .infraredObservation
        )
        try decodeValidated(self, decoder: decoder)
    }
}
