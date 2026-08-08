import CoreGraphics
import Foundation

extension ScanFrame {
    var requiresCleanedRawForActiveDefects: Bool {
        defectEdits.contains { $0.enabled && $0.strength > 1e-3 }
    }

    var boundDefectRecipeIdentity: DefectRecipeIdentity? {
        guard let identity = defectRecipeIdentity,
              identity.sourceIdentity != nil else { return nil }
        return identity
    }

    var identityMatchedCleanedRawImage: CGImage? {
        guard let identity = boundDefectRecipeIdentity,
              cleanedRawMemoryIdentity == identity else { return nil }
        return cleanedRawImage
    }

    var identityMatchedCleanedRawDiskURL: URL? {
        guard let identity = boundDefectRecipeIdentity,
              cleanedRawDiskIdentity == identity else { return nil }
        return cleanedRawDiskURL
    }
}
