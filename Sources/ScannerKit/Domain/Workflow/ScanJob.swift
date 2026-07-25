import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

// MARK: - Scan job

/// UUID/ordinal은 재시도해도 유지되고, attempt만 증가하는 한 개의 캡처 작업.
public struct ScanJob: Codable, Sendable, Equatable, Identifiable {
    public static let currentSchemaVersion = 5

    public let schemaVersion: Int
    public let id: UUID
    public let sessionID: UUID
    public let ordinal: Int
    public let attempt: Int
    public let kind: ScanJobKind
    public let state: ScanJobState
    public let requestedOptions: ScanOptions
    public let framePublication: ScanFramePublicationSnapshot?
    public let createdAt: Date
    public let updatedAt: Date
    public let startedAt: Date?
    public let finishedAt: Date?
    public let pendingCapture: PendingCaptureSnapshot?
    public let captureManifest: CaptureManifest?
    public let failure: ScannerErrorSnapshot?

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        ordinal: Int,
        attempt: Int = 1,
        kind: ScanJobKind,
        state: ScanJobState = .queued,
        requestedOptions: ScanOptions,
        framePublication: ScanFramePublicationSnapshot? = nil,
        createdAt: Date,
        updatedAt: Date? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        pendingCapture: PendingCaptureSnapshot? = nil,
        captureManifest: CaptureManifest? = nil,
        failure: ScannerErrorSnapshot? = nil
    ) throws {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.sessionID = sessionID
        self.ordinal = ordinal
        self.attempt = attempt
        self.kind = kind
        self.state = state
        self.requestedOptions = requestedOptions
        self.framePublication = framePublication
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.pendingCapture = pendingCapture
        self.captureManifest = captureManifest
        self.failure = failure
        try validate()
    }
}
