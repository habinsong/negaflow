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
    var payloadSHA256: String?

    init(snapshot: DefectRecipeSnapshot) {
        frameID = snapshot.frameID
        fingerprintVersion = snapshot.identity.fingerprintVersion
        recipeRevision = snapshot.identity.revision
        recipeSHA256 = snapshot.identity.recipeSHA256
        sourceIdentity = snapshot.identity.sourceIdentity
        // runtime fingerprint v2는 압축 표현도 포함하므로 저장 중 다시 압축하지 않습니다.
        items = snapshot.items
        payloadSHA256 = DefectSidecarPayloadDigest.sha256(items)
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
        if let payloadSHA256, payloadSHA256 != DefectSidecarPayloadDigest.sha256(items) {
            throw DefectRecipeValidationError.fingerprintMismatch
        }
        // 영속 파일은 세션 안에서 생성한 값과 달리 압축 스트림까지 검증합니다.
        _ = try DefectSidecarResourcePolicy.normalizedItems(items, limits: limits)
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
