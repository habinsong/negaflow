import CoreGraphics
import Foundation
import Chromabase

extension ScanFrame {
    var requiresCleanedRawForActiveDefects: Bool {
        defectEditsNeedRestore || defectEdits.contains { $0.enabled && $0.strength > 1e-3 }
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

    var cleanedRawDiskHasCurrentColorBasis: Bool {
        !filmType.requiresInversion || params.isDigitalSource == true
            || ImageLoader.kind(of: rawScanURL) != .rawDng
            || cleanedRawDiskURL?.lastPathComponent.hasSuffix("_raw-v2.tiff") == true
    }

    var identityMatchedCleanedRawDiskURL: URL? {
        guard cleanedRawDiskHasCurrentColorBasis else { return nil }
        guard let identity = boundDefectRecipeIdentity,
              cleanedRawDiskIdentity == identity else { return nil }
        return cleanedRawDiskURL
    }
}
