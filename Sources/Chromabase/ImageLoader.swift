import Foundation
import CoreImage
import CoreGraphics
import ImageIO

// MARK: - ImageLoader (다중 입력 포맷)
//
// 지원 입력:
//   • TIFF(8/16bit)  — 필름 스캐너 원본
//   • JPEG / PNG     — 카메라 스캔/테스트 입력
//   • DNG / RAW      — 디지털 카메라 RAW, Core Image RAW pipeline으로 현상
//
// RAW는 CGImageSourceCreateImageAtIndex로 얻으면 임베디드 썸네일만 나온다.
// 따라서 DNG/RAW는 CIRAWFilter(filterWithImageURL:)로 데모사이크 처리한다.
// 이렇게 하면 16bit linear 영역 데이터를 얻어 Chromabase 파이프라인에 그대로 넣을 수 있다.
public enum ImageLoader {
    public struct PreviewImage {
        public let image: CIImage
        public let sourcePixelSize: CGSize
        public let usesLinearSRGB: Bool

        public init(image: CIImage, sourcePixelSize: CGSize, usesLinearSRGB: Bool) {
            self.image = image
            self.sourcePixelSize = sourcePixelSize
            self.usesLinearSRGB = usesLinearSRGB
        }
    }

    /// 파일 확장자로 입력 종류 판별.
    public enum InputKind {
        case standardImage   // tiff/jpeg/png/bmp/heic ...
        case rawDng          // dng + 알려진 카메라 RAW 확장자
        case unknown
    }

    // 카메라 제조사별 RAW 확장자(소문자). 다수가 TIFF 기반이지만 CIRAWFilter로 데모사이크해야
    // 정확하다. Canon(crw/cr2/cr3) Nikon(nef/nrw) Sony(arw/srf/sr2) Fujifilm(raf)
    // Panasonic(rw2/raw) Olympus(orf) Pentax(pef) Samsung(srw) Hasselblad(3fr/fff)
    // Leica(rwl/dng) Phase One(iiq) Sigma(x3f) Epson(erf) Mamiya(mef) Leaf(mos)
    // Kodak(kdc/dcr/k25) + 범용 DNG(Apple/Google/Adobe). VueScan/SilverFast raw DNG도 여기로 온다.
    public static let rawExtensions: Set<String> = [
        "dng", "crw", "cr2", "cr3", "nef", "nrw", "arw", "srf", "sr2", "raf",
        "rw2", "raw", "orf", "pef", "srw", "3fr", "fff", "mef", "mos", "erf",
        "kdc", "dcr", "k25", "rwl", "iiq", "x3f",
    ]
    /// 표준(비-RAW) 이미지 확장자. VueScan/SilverFast raw TIFF도 여기(tiff/tif)로 온다.
    public static let standardExtensions: Set<String> = [
        "tiff", "tif", "jpeg", "jpg", "png", "heic", "heif", "bmp",
    ]
    /// 가져오기 지원 전체 확장자.
    public static var importExtensions: Set<String> { rawExtensions.union(standardExtensions) }

    public static func kind(of url: URL) -> InputKind {
        let ext = url.pathExtension.lowercased()
        if rawExtensions.contains(ext) { return .rawDng }
        if standardExtensions.contains(ext) { return .standardImage }
        // 확장자가 없거나 낯설면 UTI로 판별.
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let uti = CGImageSourceGetType(src) as String? {
            if uti == "com.adobe.raw" || uti == "public.dng" || uti.hasSuffix(".raw")
                || uti.hasSuffix("-raw-image") || uti.contains("camera-raw") {
                return .rawDng
            }
            return .standardImage
        }
        return .unknown
    }

    /// 파일을 CIImage로 로드. RAW/DNG면 데모사이크까지 수행.
    /// - Parameters:
    ///   - allowRaw: RAW 입력을 CIRAWFilter로 처리할지. false면 RAW를 거부한다.
    public static func load(_ url: URL, allowRaw: Bool = true) -> CIImage? {
        switch kind(of: url) {
        case .rawDng:
            return allowRaw ? loadRAW(url) : nil
        case .standardImage:
            return loadStandard(url)
        case .unknown:
            // 마지막 시도 — 일반 이미지로 간주.
            return loadStandard(url)
        }
    }

    /// 가져온 파일(사용자 이미지) 전용 로더 — 카메라 RAW·스캐너 raw·색상 프로필을 정확히 해석한다.
    ///
    ///   • RAW/DNG            → CIRAWFilter 데모사이크(제조사 RAW + VueScan/SilverFast raw DNG).
    ///   • 임베디드 ICC 있음   → 그 프로필로 색관리한다. SilverFast HDRi의 스캐너 프로필
    ///                           (SFprofT=투과/포지티브, SFprofN=네거티브)과 일반 색관리 이미지가 여기 해당.
    ///   • 프로필 없는 16bit+  → linear gamma 1.0 스캐너 raw 로 해석(VueScan raw TIFF 등 — 16bit raw는 gamma 1.0).
    ///   • 그 외(8bit 무프로필) → CGImage 기본 색공간(대개 sRGB) 그대로.
    ///
    /// 근거: VueScan raw는 16bit에서 linear(gamma 1.0), 8bit에서 gamma 2.2. SilverFast HDRi는
    /// linear 이며 스캐너 디바이스 프로필을 임베드한다.
    public static func loadImported(_ url: URL) -> CIImage? {
        if kind(of: url) == .rawDng { return loadRAW(url) }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            return loadStandard(url)
        }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let hasEmbeddedProfile = props?[kCGImagePropertyProfileName] != nil
        if hasEmbeddedProfile {
            // 임베디드 프로필(스캐너/작업공간)을 존중 → CoreImage가 그 프로필에서 작업공간으로 변환.
            return CIImage(cgImage: cg)
        }
        if cg.bitsPerComponent >= 16, let linear = CGColorSpace(name: CGColorSpace.linearSRGB) {
            // 프로필 없는 16bit+ = 선형 스캐너 raw(VueScan raw TIFF 등)로 해석한다.
            return CIImage(cgImage: cg, options: [.colorSpace: linear])
        }
        return CIImage(cgImage: cg)
    }

    public static func loadScannerPreview(_ url: URL, maxDimension: CGFloat,
                                          highResolutionThreshold: CGFloat) -> PreviewImage? {
        guard maxDimension > 0,
              let src = imageSource(url),
              let size = sourcePixelSize(src),
              max(size.width, size.height) > highResolutionThreshold,
              max(size.width, size.height) > maxDimension,
              let cg = thumbnail(from: src, maxDimension: maxDimension),
              let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else {
            return nil
        }
        return PreviewImage(
            image: CIImage(cgImage: cg, options: [.colorSpace: linear]),
            sourcePixelSize: size,
            usesLinearSRGB: true
        )
    }

    public static func loadImportedPreview(_ url: URL, maxDimension: CGFloat,
                                           highResolutionThreshold: CGFloat) -> PreviewImage? {
        guard maxDimension > 0,
              let src = imageSource(url),
              let size = sourcePixelSize(src),
              max(size.width, size.height) > highResolutionThreshold,
              max(size.width, size.height) > maxDimension else {
            return nil
        }
        if kind(of: url) == .rawDng {
            let scale = max(0.01, min(1.0, maxDimension / max(size.width, size.height)))
            guard let image = loadRAW(url, scaleFactor: scale) else { return nil }
            return PreviewImage(image: image, sourcePixelSize: size, usesLinearSRGB: true)
        }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let hasEmbeddedProfile = props?[kCGImagePropertyProfileName] != nil
        let sourceDepth = (props?[kCGImagePropertyDepth] as? NSNumber)?.intValue
        guard let cg = thumbnail(from: src, maxDimension: maxDimension) else { return nil }
        let linear = !hasEmbeddedProfile && max(sourceDepth ?? cg.bitsPerComponent, cg.bitsPerComponent) >= 16
        if linear, let linearSRGB = CGColorSpace(name: CGColorSpace.linearSRGB) {
            return PreviewImage(
                image: CIImage(cgImage: cg, options: [.colorSpace: linearSRGB]),
                sourcePixelSize: size,
                usesLinearSRGB: true
            )
        }
        return PreviewImage(image: CIImage(cgImage: cg), sourcePixelSize: size, usesLinearSRGB: false)
    }

    // MARK: standard (TIFF/JPEG/PNG/...)
    static func loadStandard(_ url: URL) -> CIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return CIImage(cgImage: cg)
    }

    public static func loadScannerTIFF(_ url: URL) -> CIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }
        return CIImage(cgImage: cg, options: [.colorSpace: linear])
    }

    /// 스캐너 raw 도메인(16bit linear) CGImage를 LZW 무손실 압축 TIFF로 저장한다.
    /// ICE 적용된 raw를 메모리에서 내려놓을 때 디스크 백킹으로 쓰고, `loadScannerTIFF`가 항상
    /// linearSRGB로 재해석하므로 round-trip 정밀도·색공간이 보존된다.
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
    static func loadRAW(_ url: URL, scaleFactor: CGFloat? = nil) -> CIImage? {
        // 1) CIRAWFilter 직접 생성 시도 (DNG 포함 가장 정확한 경로).
        let options = scaleFactor.map { [CIRAWFilterOption.scaleFactor: NSNumber(value: Double($0))] }
        if let filter = CIFilter(imageURL: url, options: options),
           let output = filter.value(forKey: kCIOutputImageKey) as? CIImage {
            return output
        }
        if scaleFactor != nil { return nil }
        // 2) CIRAWFilter가 실패하면 CGImageSource의 0번 인덱스로 폴백.
        //    DNG는 종종 CGImageSource로도 16bit 프리뷰를 제공한다.
        return loadStandard(url)
    }

    /// RAW 로드 시 추가 제어가 필요한 경우를 위한 진입점.
    /// exposureAdjustment/boost 같은 CIRAWFilter 파라미터를 노출한다.
    public static func loadRAWControlled(_ url: URL,
                                         exposureEV: Double = 0.0,
                                         boost: Double = 1.0) -> CIImage? {
        // CIRAWFilterOption은 Swift에서 enum 케이스로 노출된다(boostAmount 등).
        let opts: [CIRAWFilterOption: Any] = [
            .boostAmount: NSNumber(value: boost),
        ]
        if let filter = CIFilter(imageURL: url, options: opts),
           let output = filter.value(forKey: kCIOutputImageKey) as? CIImage {
            if exposureEV != 0 {
                filter.setValue(NSNumber(value: exposureEV), forKey: "inputEV")
                if let adjusted = filter.value(forKey: kCIOutputImageKey) as? CIImage {
                    return adjusted
                }
            }
            return output
        }
        return loadStandard(url)
    }

    private static func imageSource(_ url: URL) -> CGImageSource? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        return CGImageSourceCreateWithURL(url as CFURL, opts)
    }

    private static func sourcePixelSize(_ src: CGImageSource) -> CGSize? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = props[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0,
              height.doubleValue > 0 else {
            return nil
        }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    private static func thumbnail(from src: CGImageSource, maxDimension: CGFloat) -> CGImage? {
        let maxPixel = max(1, Int(maxDimension.rounded(.up)))
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}
