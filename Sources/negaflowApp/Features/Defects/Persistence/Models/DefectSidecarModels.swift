import Foundation
import CoreGraphics
import Chromabase

struct DefectSidecarV2: Codable, Sendable {
    static let currentVersion = 2

    var version: Int = currentVersion
    var frameID: UUID
    var fingerprintVersion: Int
    var recipeRevision: UInt64
    var recipeSHA256: String
    var sourceIdentity: DefectSourceIdentity?
    var items: [DefectEditItemRecord]

    init(snapshot: DefectRecipeSnapshot) {
        frameID = snapshot.frameID
        fingerprintVersion = snapshot.identity.fingerprintVersion
        recipeRevision = snapshot.identity.revision
        recipeSHA256 = snapshot.identity.recipeSHA256
        sourceIdentity = snapshot.identity.sourceIdentity
        items = snapshot.items.map { $0.compressedForStorage() }
    }

    func validatedSnapshot(
        expectedFrameID: UUID,
        limits: DefectSidecarResourceLimits = .standard
    ) throws -> DefectRecipeSnapshot {
        guard version == Self.currentVersion else {
            throw DefectRecipeValidationError.unsupportedFingerprintVersion(version)
        }
        guard frameID == expectedFrameID else {
            throw DefectRecipeValidationError.frameIDMismatch
        }
        guard fingerprintVersion == DefectRecipeFingerprint.currentVersion else {
            throw DefectRecipeValidationError.unsupportedFingerprintVersion(fingerprintVersion)
        }
        let snapshot = try DefectRecipeSnapshot(
            frameID: frameID,
            revision: recipeRevision,
            sourceIdentity: sourceIdentity,
            items: items,
            limits: limits
        )
        guard snapshot.identity.recipeSHA256 == recipeSHA256 else {
            throw DefectRecipeValidationError.fingerprintMismatch
        }
        return snapshot
    }
}

enum LoadedDefectSidecar: Equatable, Sendable {
    case legacyV1(rawData: Data, items: [DefectEditItemRecord])
    case currentV2(rawData: Data, snapshot: DefectRecipeSnapshot)

    var items: [DefectEditItemRecord] {
        switch self {
        case .legacyV1(_, let items): items
        case .currentV2(_, let snapshot): snapshot.items
        }
    }
}

enum DefectSidecarLoadResult: Equatable, Sendable {
    case missing
    case loaded(LoadedDefectSidecar)
    case unsupportedVersion(version: Int, rawData: Data)
    case invalid(rawData: Data?)
    case unreadable
}

enum DefectSidecarWriteOutcome: Equatable, Sendable {
    case written(URL)
    case alreadyCurrent(URL)
    case skippedNewer(existingRevision: UInt64)
}

enum DefectSidecarWriteError: Error, Equatable, Sendable {
    case invalidSnapshot
    case conflictingSameRevision(UInt64)
    case existingUnsupportedVersion(Int)
    case existingInvalid
    case existingUnreadable
    case legacyWriteWouldDowngrade
    case ioFailure
}

/// Canonical app-owned recipe sidecar. Writes are serialized and atomic; source image files
/// and third-party XMP sidecars are never used for this persistence layer.
