import Foundation
import CoreGraphics
import Chromabase

/// recipe 기록 파일. v2(1.2.4 이하)는 항목을 메모리 표현 그대로 담아 적외선 마스크가 비압축이었다
/// — 장당 수십 MB, 백업 세대마다 다시 그만큼. v3은 같은 snapshot 을 담되 비압축 마스크만 저장
/// 때 압축하고(`storagePacked`) 읽을 때 되돌린다. 둘 다 읽고, 쓰기는 v3 만 한다.
struct DefectSidecarV2: Codable, Sendable {
    static let currentVersion = 3
    static let unpackedVersion = 2
    static let readableVersions: ClosedRange<Int> = unpackedVersion...currentVersion

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
        // 지문은 메모리 표현(압축 여부 포함) 기준이다. 저장 압축은 표시를 달아 읽을 때 되돌린다.
        items = snapshot.items.map { $0.packedForStorage() }
    }

    func validatedSnapshot(
        expectedFrameID: UUID,
        limits: DefectSidecarResourceLimits = .standard
    ) throws -> DefectRecipeSnapshot {
        guard Self.readableVersions.contains(version) else {
            throw DefectRecipeValidationError.unsupportedFingerprintVersion(version)
        }
        guard frameID == expectedFrameID else {
            throw DefectRecipeValidationError.frameIDMismatch
        }
        guard fingerprintVersion == DefectRecipeFingerprint.currentVersion else {
            throw DefectRecipeValidationError.unsupportedFingerprintVersion(fingerprintVersion)
        }
        let items: [DefectEditItemRecord]
        if version == Self.unpackedVersion {
            // v2 기록기는 저장 압축을 몰랐다. 표시가 있으면 손으로 만든 파일이다.
            guard !self.items.contains(where: \.hasStoragePackedPayload) else {
                throw DefectRecipeValidationError.invalidMask
            }
            items = self.items
        } else {
            var remainingBytes = limits.maxFileBytes
            items = try self.items.map {
                try $0.unpackedFromStorage(remainingBytes: &remainingBytes, limits: limits)
            }
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
