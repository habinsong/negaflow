import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import Chromabase

// MARK: - Scan session

/// 한 장치/백엔드 스냅샷에 잠긴 순서 있는 캡처 작업 집합.
public struct ScanSession: Codable, Sendable, Equatable, Identifiable {
    public static let currentSchemaVersion = 4

    public let schemaVersion: Int
    public let id: UUID
    public let createdAt: Date
    public let closedAt: Date?
    public let device: ScannerDescriptor
    public let backend: ScanBackendSnapshot
    public let environment: ScanEnvironmentSnapshot
    public let jobs: [ScanJob]

    public init(
        id: UUID = UUID(),
        createdAt: Date,
        closedAt: Date? = nil,
        device: ScannerDescriptor,
        backend: ScanBackendSnapshot,
        environment: ScanEnvironmentSnapshot,
        jobs: [ScanJob] = []
    ) throws {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.createdAt = createdAt
        self.closedAt = closedAt
        self.device = device
        self.backend = backend
        self.environment = environment
        self.jobs = jobs
        try validate()
    }
}
