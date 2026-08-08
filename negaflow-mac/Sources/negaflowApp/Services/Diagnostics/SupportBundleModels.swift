import Foundation

struct SupportBundleDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let generatedAt: Date
    let redactionPolicy: String
    let app: SupportBundleAppSummary
    let locations: SupportBundleLocationSummary
    let catalog: SupportBundleCatalogSummary
    let backup: SupportBundleBackupSummary
    let cache: SupportBundleCacheSummary
    let plugins: [SupportBundlePluginSummary]
    let scanner: SupportBundleScannerSummary?
    let recentErrors: [AppDiagnosticEvent]
}

struct SupportBundleAppSummary: Codable, Equatable, Sendable {
    let version: String
    let osVersion: String
    let architecture: String
    let activeProcessorCount: Int
    let physicalMemoryBytes: UInt64
}

struct SupportBundleLocationSummary: Codable, Equatable, Sendable {
    let catalogHash: String
    let scanOriginalsHash: String
    let thumbnailCacheHash: String
    let scanStorageKind: String
}

struct SupportBundleCatalogIssueCount: Codable, Equatable, Sendable {
    let code: String
    let severity: String
    let count: Int
}

struct SupportBundleCatalogSummary: Codable, Equatable, Sendable {
    let lifecycle: String
    let blockReason: String?
    let snapshotAvailable: Bool
    let catalogVersion: Int
    let frameCount: Int
    let rollCount: Int
    let folderCount: Int
    let warningCount: Int
    let errorCount: Int
    let issues: [SupportBundleCatalogIssueCount]
}

struct SupportBundleBackupGeneration: Codable, Equatable, Sendable {
    let sequence: UInt64?
    let createdAt: Date?
    let state: String
    let frameCount: Int?
    let defectRecipeCount: Int?
    let catalogVersion: Int?
}

struct SupportBundleBackupSummary: Codable, Equatable, Sendable {
    let schedule: String
    let externalDestinationConfigured: Bool
    let lastAttemptAt: Date?
    let lastSuccessAt: Date?
    let lastRestoreDrillSucceeded: Bool?
    let generations: [SupportBundleBackupGeneration]
}

struct SupportBundleCacheSummary: Codable, Equatable, Sendable {
    let thumbnailBytes: Int64
    let cleanedRawBytes: Int64
    let residentCleanedRawCount: Int
    let residentDevelopedCount: Int
    let maxResidentCleanedRaw: Int
    let maxResidentDeveloped: Int
}

struct SupportBundlePluginSummary: Codable, Equatable, Sendable {
    let pluginIDHash: String
    let pluginVersion: String?
    let schemaVersion: Int
    let protocolVersion: Int
    let supportedByHost: Bool
    let approvalState: String
    let manifestSHA256: String?
    let executableSHA256: String?
}

struct SupportBundleScannerSummary: Codable, Equatable, Sendable {
    let resolutionsDPI: [Int]
    let modes: [String]
    let bitDepths: [Int]
    let supportsPreview: Bool
    let supportsTransparency: Bool
    let supportsInfrared: Bool
    let supportsMultiExposure: Bool
    let supportsScanArea: Bool
}
