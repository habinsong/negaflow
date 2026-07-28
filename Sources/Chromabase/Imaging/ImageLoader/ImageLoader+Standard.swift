import Foundation
import CoreImage
import CoreGraphics
import ImageIO

extension ImageLoader {
    static func loadStandard(_ url: URL) -> CIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        // 프로필 없는 16bit+ TIFF는 스캐너 raw(linear)다 — 경로가 달라도 같은 파일은 같게 읽어야 한다.
        let base = profileAwareImage(cg, properties: props, untaggedTIFFRole: .linearScannerRaw)
        // EXIF orientation 반영(orientation 1이면 무연산). 스캐너 raw 경로(loadScannerTIFF)는 별도라 영향 없음.
        let exif = exifOrientation(props)
        return exif == 1 ? base : base.oriented(forExifOrientation: exif)
    }

    public static func loadScannerTIFF(_ url: URL) -> CIImage? {
        loadScannerTIFFDecoded(url)?.image
    }

    public static func loadScannerTIFFDecoded(_ url: URL) -> DecodedImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        return DecodedImage(
            image: profileAwareImage(
                cg,
                properties: props,
                untaggedTIFFRole: .linearScannerRaw
            ),
            provenance: DecodeProvenance(
                decoder: .imageIO,
                untaggedTIFFRole: untaggedTIFFRoleIfApplicable(
                    cg,
                    properties: props,
                    requestedRole: .linearScannerRaw
                )
            )
        )
    }

    /// 스캐너 raw 도메인(16bit linear) CGImage를 LZW 무손실 압축 TIFF로 저장한다.
    /// 결함 제거된 raw를 메모리에서 내려놓을 때 디스크 백킹으로 쓴다. 저장 CGImage의 linear
    /// 프로필을 유지하고, 프로필이 없는 16bit 파일도 `loadScannerTIFF`가 linear로 해석한다.
    @discardableResult
    public static func saveScannerTIFF(_ cg: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil)
        else { return false }
        let props: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5],  // 5 = LZW
        ]
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    // MARK: RAW / DNG
    //
    // CIRAWFilter는 디지털 카메라 RAW를 16bit linear로 전개한다.
    // 기본 디폴트(노출 0, 화이트밸런스 카메라 기준)로 로드한 뒤
    // 추가 튜닝은 Chromabase 파이프라인에서 수행한다.
}
