import Foundation
import CoreImage
import CoreGraphics
import ImageIO

extension ImageLoader {
    static func imageSource(_ url: URL) -> CGImageSource? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        return CGImageSourceCreateWithURL(url as CFURL, opts)
    }

    /// 스캐너 raw와 일반 가져오기 양쪽에 같은 입력 색상 규칙을 적용한다. Image I/O가 보고한
    /// 임베디드 ICC는 그대로 두어 Core Image가 작업 색공간으로 변환하게 하고, 프로필 없는
    /// 16bit+ 픽셀만 VueScan 계열 linear raw로 해석한다.
    static func profileAwareImage(
        _ cg: CGImage,
        properties: [CFString: Any]?,
        untaggedTIFFRole: UntaggedTIFFRole
    ) -> CIImage {
        if untaggedTIFFRole == .linearScannerRaw,
           shouldInterpretAsLinearRaw(cg, properties: properties),
           let linear = CGColorSpace(name: CGColorSpace.linearSRGB) {
            return CIImage(cgImage: cg, options: [.colorSpace: linear])
        }
        return CIImage(cgImage: cg)
    }

    static func untaggedTIFFRoleIfApplicable(
        _ cg: CGImage,
        properties: [CFString: Any]?,
        requestedRole: UntaggedTIFFRole
    ) -> UntaggedTIFFRole? {
        shouldInterpretAsLinearRaw(cg, properties: properties) ? requestedRole : nil
    }

    static func shouldInterpretAsLinearRaw(
        _ cg: CGImage,
        properties: [CFString: Any]?
    ) -> Bool {
        guard properties?[kCGImagePropertyTIFFDictionary] != nil,
              properties?[kCGImagePropertyProfileName] == nil else { return false }
        return sourceBitDepth(cg, properties: properties) >= 16
    }

    static func sourceBitDepth(
        _ cg: CGImage,
        properties: [CFString: Any]?
    ) -> Int {
        let sourceDepth = (properties?[kCGImagePropertyDepth] as? NSNumber)?.intValue
        return max(sourceDepth ?? cg.bitsPerComponent, cg.bitsPerComponent)
    }

    static func rawImageSourceType(of url: URL) -> String? {
        guard let src = imageSource(url),
              let uti = CGImageSourceGetType(src) as String?,
              isRawImageSourceType(uti) else { return nil }
        return uti
    }

    static func isRawImageSourceType(_ uti: String) -> Bool {
        uti == "com.adobe.raw" || uti == "com.adobe.raw-image" || uti == "public.dng"
            || uti.hasSuffix(".raw") || uti.hasSuffix(".raw-image")
            || uti.hasSuffix("-raw-image") || uti.contains("camera-raw")
    }

    static func sourcePixelSize(_ src: CGImageSource) -> CGSize? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = props[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0,
              height.doubleValue > 0 else {
            return nil
        }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    static func thumbnail(
        from src: CGImageSource,
        maxDimension: CGFloat,
        applyOrientation: Bool
    ) -> CGImage? {
        let maxPixel = max(1, Int(maxDimension.rounded(.up)))
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            // 가져온 이미지만 EXIF orientation을 썸네일 픽셀에 굽는다. 스캐너 경로는 장치/세션
            // orientation을 별도 비파괴 transform으로 관리하므로 메타데이터 회전을 중복 적용하지 않는다.
            kCGImageSourceCreateThumbnailWithTransform: applyOrientation,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// CGImageSource 속성에서 EXIF orientation(1...8)을 읽는다. 없으면 1(정립).
    static func exifOrientation(_ props: [CFString: Any]?) -> Int32 {
        (props?[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
    }
}
