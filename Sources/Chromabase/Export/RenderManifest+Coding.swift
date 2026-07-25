import Foundation

extension RenderManifest {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        source = try container.decode(SourceIdentity.self, forKey: .source)
        developRecipeSHA256 = try container.decode(String.self, forKey: .developRecipeSHA256)
        scannerProfileID = try container.decodeIfPresent(String.self, forKey: .scannerProfileID)
        scannerProfileHash = try container.decodeIfPresent(String.self, forKey: .scannerProfileHash)
        rendererVersion = try container.decode(String.self, forKey: .rendererVersion)
        renderInputKind = try container.decodeIfPresent(
            RenderInputKind.self,
            forKey: .renderInputKind
        ) ?? .source
        renderInput = try container.decodeIfPresent(SourceIdentity.self, forKey: .renderInput)
        coverage = try container.decodeIfPresent(Coverage.self, forKey: .coverage)
            ?? .completeRenderInput
        decodeProvenance = try container.decodeIfPresent(
            ImageLoader.DecodeProvenance.self,
            forKey: .decodeProvenance
        )
        defectRecipeSHA256 = try container.decodeIfPresent(
            String.self,
            forKey: .defectRecipeSHA256
        )
        exportRecipeSHA256 = try container.decodeIfPresent(
            String.self,
            forKey: .exportRecipeSHA256
        )
        outputProfileSHA256 = try container.decodeIfPresent(
            String.self,
            forKey: .outputProfileSHA256
        )
        outputArtifact = try container.decodeIfPresent(
            OutputArtifact.self,
            forKey: .outputArtifact
        )
    }
}
