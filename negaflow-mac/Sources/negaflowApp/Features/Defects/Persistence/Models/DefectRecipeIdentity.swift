import Foundation
import CoreGraphics
import Chromabase

enum DefectRecipeValidationError: Error, Equatable, Sendable {
    case invalidSourceIdentity
    case invalidRevision
    case invalidRecipeSHA256
    case unsupportedFingerprintVersion(Int)
    case invalidRecordShape
    case invalidScalar
    case invalidStrength
    case invalidMask
    case frameIDMismatch
    case fingerprintMismatch
    case resourceLimitExceeded(DefectSidecarResource)
}

/// 경로와 무관한 원본 파일 identity. Source relink 뒤에도 동일 바이트인지 비교할 수 있다.
struct DefectSourceIdentity: Codable, Equatable, Sendable {
    let byteCount: UInt64
    let sha256: String

    init(byteCount: UInt64, sha256: String) throws {
        guard byteCount > 0, Self.isValidSHA256(sha256) else {
            throw DefectRecipeValidationError.invalidSourceIdentity
        }
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    private enum CodingKeys: String, CodingKey {
        case byteCount
        case sha256
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            byteCount: container.decode(UInt64.self, forKey: .byteCount),
            sha256: container.decode(String.self, forKey: .sha256)
        )
    }

    private static func isValidSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}

struct DefectRecipeIdentity: Codable, Equatable, Sendable {
    let fingerprintVersion: Int
    let revision: UInt64
    let recipeSHA256: String
    let sourceIdentity: DefectSourceIdentity?

    init(
        fingerprintVersion: Int,
        revision: UInt64,
        recipeSHA256: String,
        sourceIdentity: DefectSourceIdentity?
    ) throws {
        guard fingerprintVersion == DefectRecipeFingerprint.currentVersion else {
            throw DefectRecipeValidationError.unsupportedFingerprintVersion(fingerprintVersion)
        }
        guard revision > 0 else { throw DefectRecipeValidationError.invalidRevision }
        guard recipeSHA256.utf8.count == 64,
              recipeSHA256.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (97...102).contains(byte)
              }) else {
            throw DefectRecipeValidationError.invalidRecipeSHA256
        }
        self.fingerprintVersion = fingerprintVersion
        self.revision = revision
        self.recipeSHA256 = recipeSHA256
        self.sourceIdentity = sourceIdentity
    }

    private enum CodingKeys: String, CodingKey {
        case fingerprintVersion
        case revision
        case recipeSHA256
        case sourceIdentity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            fingerprintVersion: container.decode(Int.self, forKey: .fingerprintVersion),
            revision: container.decode(UInt64.self, forKey: .revision),
            recipeSHA256: container.decode(String.self, forKey: .recipeSHA256),
            sourceIdentity: container.decodeIfPresent(
                DefectSourceIdentity.self,
                forKey: .sourceIdentity
            )
        )
    }
}

struct DefectRecipeSnapshot: Equatable, Sendable {
    let frameID: UUID
    let identity: DefectRecipeIdentity
    /// fingerprint가 검증한 record(마스크는 저장 형태 그대로 — 압축 해제하지 않는다).
    let items: [DefectEditItemRecord]

    init(
        frameID: UUID,
        revision: UInt64,
        sourceIdentity: DefectSourceIdentity?,
        items: [DefectEditItemRecord],
        limits: DefectSidecarResourceLimits = .standard
    ) throws {
        // 개수 상한 검증만 수행한다. 마스크 압축 해제(수십~수백 MB)는 편집 hot path에서
        // 제거됐다 — fingerprint v2가 마스크 내용 대신 항목 UUID/형태를 쓴다.
        let checkedItems = try DefectSidecarResourcePolicy.checkedItems(
            items,
            limits: limits
        )
        let recipeSHA256 = try DefectRecipeFingerprint.sha256(items: checkedItems)
        self.frameID = frameID
        self.identity = try DefectRecipeIdentity(
            fingerprintVersion: DefectRecipeFingerprint.currentVersion,
            revision: revision,
            recipeSHA256: recipeSHA256,
            sourceIdentity: sourceIdentity
        )
        self.items = checkedItems
    }
}

/// v2 on-disk document. Frozen v1 `DefectSidecar`와 이름/shape를 분리해 기존 binary plist를
/// 읽거나 백업할 때 재인코딩하지 않는다.
