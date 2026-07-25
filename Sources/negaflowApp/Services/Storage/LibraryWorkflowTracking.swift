import CryptoKit
import Foundation
import Chromabase

enum LibraryTrackingCoverage: String, Codable, Equatable, Sendable {
    case legacyUnknown
    case tracked
}

struct LibraryUserEditTracking: Codable, Equatable, Sendable {
    var coverage: LibraryTrackingCoverage
    var ingestRecipeSHA256: String?
    var currentRecipeSHA256: String?
    var revision: UInt64

    static func legacyUnknown(currentRecipeSHA256: String? = nil) -> Self {
        Self(
            coverage: .legacyUnknown,
            ingestRecipeSHA256: nil,
            currentRecipeSHA256: currentRecipeSHA256,
            revision: 0
        )
    }
}

struct LibraryExportEvent: Codable, Equatable, Sendable, Identifiable {
    enum RenderKind: String, Codable, Equatable, Sendable {
        case developed
        case rawSource
    }

    var id: UUID
    var completedAt: Date
    var primaryOutputPath: String
    var artifactPaths: [String]
    var formatRawValue: String
    /// raw source copy는 develop recipe를 적용하지 않는다.
    var renderKind: RenderKind
    var developRecipeSHA256: String?
    var defectRecipeSHA256: String?
    /// 새 export가 사용한 원본 세대. nil은 이 필드가 없던 legacy catalog event만 의미한다.
    var sourceIdentity: RenderManifest.SourceIdentity? = nil
    var exportRecipePresetID: UUID? = nil
    var exportRecipeSHA256: String? = nil
}

struct LibraryExportTracking: Codable, Equatable, Sendable {
    var coverage: LibraryTrackingCoverage
    var successfulEvents: [LibraryExportEvent]

    static let legacyUnknown = Self(
        coverage: .legacyUnknown,
        successfulEvents: []
    )
}

struct LibraryDefectReviewTracking: Codable, Equatable, Sendable {
    var coverage: LibraryTrackingCoverage
    /// Sidecar v2 연결 전 legacy frame은 둘 다 nil이다. 둘 중 하나만 존재하는 상태는
    /// 다음 health 단계에서 fail closed한다.
    var currentRecipeRevision: UInt64?
    var currentRecipeSHA256: String?
    /// source relink가 다른 픽셀로 바뀌어도 같은 recipe hash만으로 reviewed가 되지 않게 한다.
    var currentSourceIdentitySHA256: String?
    var reviewedRecipeRevision: UInt64?
    var reviewedRecipeSHA256: String?
    var reviewedSourceIdentitySHA256: String?

    static let legacyUnknown = Self(
        coverage: .legacyUnknown,
        currentRecipeRevision: nil,
        currentRecipeSHA256: nil,
        currentSourceIdentitySHA256: nil,
        reviewedRecipeRevision: nil,
        reviewedRecipeSHA256: nil,
        reviewedSourceIdentitySHA256: nil
    )
}

struct LibraryFrameWorkflowTrackingState: Equatable, Sendable {
    var userEditTracking: LibraryUserEditTracking
    var exportTracking: LibraryExportTracking
    var defectReviewTracking: LibraryDefectReviewTracking

    static func newFrame(currentRecipeSHA256: String) -> Self {
        Self(
            userEditTracking: LibraryUserEditTracking(
                coverage: .tracked,
                ingestRecipeSHA256: currentRecipeSHA256,
                currentRecipeSHA256: currentRecipeSHA256,
                revision: 0
            ),
            exportTracking: LibraryExportTracking(
                coverage: .tracked,
                successfulEvents: []
            ),
            defectReviewTracking: LibraryDefectReviewTracking(
                coverage: .tracked,
                currentRecipeRevision: nil,
                currentRecipeSHA256: nil,
                currentSourceIdentitySHA256: nil,
                reviewedRecipeRevision: nil,
                reviewedRecipeSHA256: nil,
                reviewedSourceIdentitySHA256: nil
            )
        )
    }

    func reconciled(currentRecipeSHA256: String) -> Self? {
        guard userEditTracking.currentRecipeSHA256 != currentRecipeSHA256 else {
            return self
        }
        guard userEditTracking.revision < UInt64.max,
              let previousRecipeSHA256 = userEditTracking.currentRecipeSHA256 else {
            return nil
        }
        var updated = self
        switch userEditTracking.coverage {
        case .legacyUnknown:
            updated.userEditTracking = LibraryUserEditTracking(
                coverage: .tracked,
                ingestRecipeSHA256: previousRecipeSHA256,
                currentRecipeSHA256: currentRecipeSHA256,
                revision: 1
            )
        case .tracked:
            updated.userEditTracking.currentRecipeSHA256 = currentRecipeSHA256
            updated.userEditTracking.revision += 1
        }
        return updated
    }
}

struct LibraryManualCollection: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var frameIDs: [UUID]
}

struct LibrarySmartCollection: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var definition: LibraryStoredSearchEnvelope
}

struct LibrarySavedSearch: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var definition: LibraryStoredSearchEnvelope
}

enum LibraryStoredSearchEnvelopeError: Error, Equatable {
    case payloadTooLarge
}

/// Query payload를 catalog의 구조 decode와 분리한다. payload 하나가 손상되거나 미래
/// LibraryQuery 버전이어도 outer catalog와 다른 저장 검색은 그대로 보존할 수 있다.
struct LibraryStoredSearchEnvelope: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let maximumPayloadUTF8Bytes = 131_072

    var version: Int
    var payloadJSON: String

    init(version: Int = currentVersion, payloadJSON: String) {
        self.version = version
        self.payloadJSON = payloadJSON
    }

    init(definition: LibrarySearchDefinition) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(definition)
        guard data.count <= Self.maximumPayloadUTF8Bytes,
              let payloadJSON = String(data: data, encoding: .utf8) else {
            throw LibraryStoredSearchEnvelopeError.payloadTooLarge
        }
        self.init(payloadJSON: payloadJSON)
    }

    func decodedDefinition() -> LibrarySearchDefinition? {
        guard version == Self.currentVersion,
              payloadJSON.utf8.count <= Self.maximumPayloadUTF8Bytes,
              let data = payloadJSON.data(using: .utf8),
              let definition = try? JSONDecoder().decode(
                  LibrarySearchDefinition.self,
                  from: data
              ),
              definition.version == LibrarySearchDefinition.currentVersion,
              definition.query.isValid else {
            return nil
        }
        return definition
    }
}

struct LibrarySearchDefinition: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var query: LibraryQuery
    var sort: LibrarySortDescriptor

    init(
        version: Int = currentVersion,
        query: LibraryQuery,
        sort: LibrarySortDescriptor
    ) {
        self.version = version
        self.query = query
        self.sort = sort
    }
}

enum LibraryDevelopRecipeFingerprint {
    static let currentVersion = 1

    private struct Payload: Codable {
        var version: Int
        var presetID: String?
        var parameters: DevelopParameters
    }

    static func sha256(
        filmType: FilmType,
        presetID: String?,
        params: DevelopParameters,
        imageTransform: ImageTransform
    ) throws -> String {
        var normalized = params
        normalized.filmType = filmType
        normalized.imageTransform = imageTransform
        let payload = Payload(
            version: currentVersion,
            presetID: presetID,
            parameters: normalized
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let digest = SHA256.hash(data: try encoder.encode(payload))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

struct LibraryDevelopRecipeFingerprintCacheKey: Equatable {
    var filmType: FilmType
    var presetID: String?
    var params: DevelopParameters
    var imageTransform: ImageTransform
}
