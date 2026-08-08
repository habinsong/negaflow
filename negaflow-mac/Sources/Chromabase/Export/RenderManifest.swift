import Foundation

/// 원본, 실제 render input, recipe와 최종 산출물을 경로 없이 연결하는 재현성 계약.
/// 이 JSON 자체는 서명된 C2PA claim이 아니며, SHA-256 hard binding에 필요한 사실만 기록한다.
public struct RenderManifest: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 3

    public var schemaVersion: Int
    public var source: SourceIdentity
    public var developRecipeSHA256: String
    public var scannerProfileID: String?
    public var scannerProfileHash: String?
    public var rendererVersion: String
    public var renderInputKind: RenderInputKind
    public var renderInput: SourceIdentity?
    public var coverage: Coverage
    public var decodeProvenance: ImageLoader.DecodeProvenance?
    public var defectRecipeSHA256: String?
    public var exportRecipeSHA256: String?
    public var outputProfileSHA256: String?
    public var outputArtifact: OutputArtifact?

    public init(
        schemaVersion: Int = currentSchemaVersion,
        source: SourceIdentity,
        developRecipeSHA256: String,
        scannerProfileID: String?,
        scannerProfileHash: String?,
        rendererVersion: String,
        renderInputKind: RenderInputKind = .source,
        renderInput: SourceIdentity? = nil,
        coverage: Coverage = .completeRenderInput,
        decodeProvenance: ImageLoader.DecodeProvenance? = nil,
        defectRecipeSHA256: String? = nil,
        exportRecipeSHA256: String? = nil,
        outputProfileSHA256: String? = nil,
        outputArtifact: OutputArtifact? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.source = source
        self.developRecipeSHA256 = developRecipeSHA256
        self.scannerProfileID = scannerProfileID
        self.scannerProfileHash = scannerProfileHash
        self.rendererVersion = rendererVersion
        self.renderInputKind = renderInputKind
        self.renderInput = renderInput
        self.coverage = coverage
        self.decodeProvenance = decodeProvenance
        self.defectRecipeSHA256 = defectRecipeSHA256
        self.exportRecipeSHA256 = exportRecipeSHA256
        self.outputProfileSHA256 = outputProfileSHA256
        self.outputArtifact = outputArtifact
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, source, developRecipeSHA256, scannerProfileID, scannerProfileHash
        case rendererVersion, renderInputKind, renderInput, coverage, decodeProvenance
        case defectRecipeSHA256, exportRecipeSHA256, outputProfileSHA256, outputArtifact
    }
}
