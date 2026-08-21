import Foundation
import CoreImage
import CoreGraphics
import ImageIO

extension ImageLoader {
    static func loadStandard(_ url: URL) -> CIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = createFullyDecodedImage(src) else { return nil }
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
              let cg = createFullyDecodedImage(src) else { return nil }
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

    /// 스캐너 raw 도메인(16bit linear) CGImage를 비압축 TIFF로 저장한다.
    /// 결함 제거된 raw를 메모리에서 내려놓을 때 디스크 백킹으로 쓰고, 종료 시 굽기가 사용자
    /// 원본을 이 형식으로 교체한다. 저장 CGImage의 linear 프로필을 유지하고, 프로필이 없는
    /// 16bit 파일도 `loadScannerTIFF`가 linear로 해석한다.
    ///
    /// **압축하지 않는 이유**: 예전에는 LZW 를 걸었는데, 16bit 연속톤에서는 인접 픽셀이 전부
    /// 미세하게 다르고 한 픽셀이 두 바이트로 쪼개져 반복 패턴이 없다. 실측(5088×3401, 흑백
    /// 네거티브·슬라이드·컬러 네거티브 6장)에서 LZW 파일이 오히려 10~15% **크고** 저장은
    /// 9~16배(≈130ms → ≈1,300ms) 느렸다. 이 저장은 결함 편집 커밋마다, 그리고 종료 시 프레임마다
    /// 일어나므로 그 시간이 그대로 사용자 대기가 된다. 기존 LZW 파일은 그대로 읽힌다.
    ///
    /// raw 도메인에는 알파가 없으므로 Core Image 그래프가 붙인 알파는 벗기고 저장한다
    /// (`opaqueRawImage` — 4채널로 굳으면 파일이 커지고 다시 읽는 쪽이 느려진다).
    @discardableResult
    public static func saveScannerTIFF(_ cg: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil)
        else { return false }
        let props: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 1],  // 1 = 비압축
        ]
        CGImageDestinationAddImage(dest, opaqueRawImage(cg), props as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    // MARK: RAW / DNG
    //
    // CIRAWFilter는 디지털 카메라 RAW를 16bit linear로 전개한다.
    // 기본 디폴트(노출 0, 화이트밸런스 카메라 기준)로 로드한 뒤
    // 추가 튜닝은 Chromabase 파이프라인에서 수행한다.
}
