import Foundation
import ImageIO
import Chromabase

enum RenderManifestArtifactInspector {
    static func inspect(
        _ url: URL,
        format: ExportFormat,
        expectedOutputProfileSHA256: String? = nil
    ) throws -> RenderManifest.OutputArtifact {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0 else {
            throw ChromabaseError.writeFailed("rendered artifact metadata is unavailable")
        }
        if let expectedOutputProfileSHA256,
           ICCOutputProfileSnapshot.embeddedProfileSHA256(at: url)
                != expectedOutputProfileSHA256 {
            throw ChromabaseError.writeFailed("rendered artifact ICC profile does not match request")
        }
        return RenderManifest.OutputArtifact(
            identity: try RenderManifest.sourceIdentity(for: url),
            format: format,
            pixelWidth: width,
            pixelHeight: height
        )
    }
}
