import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

// MARK: - Capture manifest

/// 성공한 한 번의 캡처 시도를 재구성할 수 있는 provenance manifest.
public struct CaptureManifest: Codable, Sendable, Equatable, Identifiable {
    public static let currentSchemaVersion = 4

    public let schemaVersion: Int
    public let id: UUID
    public let sessionID: UUID
    public let jobID: UUID
    public let attempt: Int
    public let kind: ScanJobKind
    public let requestedOptions: ScanOptions
    public let appliedOptionsEvidence: AppliedScanOptionsEvidence
    public let result: CaptureResultSnapshot
    public let captureStartedAt: Date
    public let captureCompletedAt: Date
    public let rgbFile: CaptureFileIdentity
    public let infraredFile: CaptureFileIdentity?
    public let rgbObservation: CaptureFileObservation
    public let infraredObservation: CaptureFileObservation?

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        jobID: UUID,
        attempt: Int,
        kind: ScanJobKind,
        requestedOptions: ScanOptions,
        appliedOptionsEvidence: AppliedScanOptionsEvidence,
        result: CaptureResultSnapshot,
        captureStartedAt: Date,
        captureCompletedAt: Date,
        rgbFile: CaptureFileIdentity,
        infraredFile: CaptureFileIdentity? = nil,
        rgbObservation: CaptureFileObservation? = nil,
        infraredObservation: CaptureFileObservation? = nil
    ) throws {
        let resolvedRGBObservation: CaptureFileObservation
        if let rgbObservation {
            resolvedRGBObservation = rgbObservation
        } else {
            resolvedRGBObservation = try CaptureFileObservation.capture(for: rgbFile.originalURL)
        }
        let resolvedInfraredObservation: CaptureFileObservation?
        if let infraredObservation {
            resolvedInfraredObservation = infraredObservation
        } else if let infraredFile {
            resolvedInfraredObservation = try CaptureFileObservation.capture(
                for: infraredFile.originalURL
            )
        } else {
            resolvedInfraredObservation = nil
        }
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.sessionID = sessionID
        self.jobID = jobID
        self.attempt = attempt
        self.kind = kind
        self.requestedOptions = requestedOptions
        self.appliedOptionsEvidence = appliedOptionsEvidence
        self.result = result
        self.captureStartedAt = captureStartedAt
        self.captureCompletedAt = captureCompletedAt
        self.rgbFile = rgbFile
        self.infraredFile = infraredFile
        self.rgbObservation = resolvedRGBObservation
        self.infraredObservation = resolvedInfraredObservation
        try validate()
        try verifyCurrentFiles()
    }
}
