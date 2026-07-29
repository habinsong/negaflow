import Foundation
import ImageIO
import Chromabase

enum RenderManifestArtifactInspector {
    /// 산출물의 픽셀 크기와(요청 시) 임베드된 출력 ICC 가 기대와 같은지 확인한다.
    /// 전체 바이트 해시는 계산하지 않는다.
    @discardableResult
    static func validate(
        _ url: URL,
        expectedOutputProfileSHA256: String? = nil
    ) throws -> (width: Int, height: Int) {
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
        return (width, height)
    }

    static func inspect(
        _ url: URL,
        format: ExportFormat,
        expectedOutputProfileSHA256: String? = nil
    ) throws -> RenderManifest.OutputArtifact {
        let size = try validate(url, expectedOutputProfileSHA256: expectedOutputProfileSHA256)
        return RenderManifest.OutputArtifact(
            identity: try RenderManifest.sourceIdentity(for: url),
            format: format,
            pixelWidth: size.width,
            pixelHeight: size.height
        )
    }
}
