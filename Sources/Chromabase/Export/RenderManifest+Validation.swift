import Foundation

public enum RenderManifestValidationError: Error, Equatable, Sendable {
    case invalidChunkSize
    case sourceChangedDuringHash
    case unsupportedSchemaVersion(Int)
    case invalidSourceIdentity
    case invalidRecipeHash(String)
    case invalidScannerProfileHash
    case inconsistentRenderInput
    case missingDefectRecipeHash
    case missingOutputArtifact
    case invalidOutputArtifact
    case missingRendererVersion
}

extension RenderManifest {
    public func validate() throws {
        guard (1...Self.currentSchemaVersion).contains(schemaVersion) else {
            throw RenderManifestValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        guard Self.isValid(source) else {
            throw RenderManifestValidationError.invalidSourceIdentity
        }
        try Self.requireHash(developRecipeSHA256, field: "developRecipeSHA256")
        if let scannerProfileHash {
            guard scannerProfileID != nil, Self.isSHA256(scannerProfileHash) else {
                throw RenderManifestValidationError.invalidScannerProfileHash
            }
        }
        if let defectRecipeSHA256 {
            try Self.requireHash(defectRecipeSHA256, field: "defectRecipeSHA256")
        }
        if let exportRecipeSHA256 {
            try Self.requireHash(exportRecipeSHA256, field: "exportRecipeSHA256")
        }
        if let outputProfileSHA256 {
            try Self.requireHash(outputProfileSHA256, field: "outputProfileSHA256")
        }
        guard !rendererVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RenderManifestValidationError.missingRendererVersion
        }
        try validateInputContract()
        if schemaVersion >= 3 {
            guard let outputArtifact else {
                throw RenderManifestValidationError.missingOutputArtifact
            }
            guard Self.isValid(outputArtifact.identity),
                  outputArtifact.pixelWidth > 0,
                  outputArtifact.pixelHeight > 0 else {
                throw RenderManifestValidationError.invalidOutputArtifact
            }
        } else if let outputArtifact,
                  !Self.isValid(outputArtifact.identity)
                    || outputArtifact.pixelWidth <= 0
                    || outputArtifact.pixelHeight <= 0 {
            throw RenderManifestValidationError.invalidOutputArtifact
        }
    }

    private func validateInputContract() throws {
        switch (renderInputKind, renderInput, coverage) {
        case (.source, nil, .completeRenderInput):
            break
        case (.cleanedFile, .some(let identity), .completeRenderInput):
            guard Self.isValid(identity) else {
                throw RenderManifestValidationError.inconsistentRenderInput
            }
        case (.cleanedMemory, nil, .sourceAndDevelopRecipe):
            break
        default:
            throw RenderManifestValidationError.inconsistentRenderInput
        }
        if schemaVersion >= 3,
           renderInputKind != .source,
           defectRecipeSHA256 == nil {
            throw RenderManifestValidationError.missingDefectRecipeHash
        }
    }

    private static func isValid(_ identity: SourceIdentity) -> Bool {
        identity.algorithm == .sha256
            && identity.byteCount >= 0
            && isSHA256(identity.sha256)
    }

    private static func requireHash(_ value: String, field: String) throws {
        guard isSHA256(value) else {
            throw RenderManifestValidationError.invalidRecipeHash(field)
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}
