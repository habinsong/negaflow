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
    /// 파일 확장자로 입력 종류 판별.
    public enum InputKind {
        case standardImage   // tiff/jpeg/png/bmp/heic ...
        case rawDng          // dng + 알려진 RAW 확장자
        case unknown
    }

    public static func kind(of url: URL) -> InputKind {
        let ext = url.pathExtension.lowercased()
        let rawExts: Set<String> = ["dng", "raw", "cr2", "cr3", "nef", "arw",
                                    "raf", "orf", "rw2", "pef", "srw", "3fr"]
        if rawExts.contains(ext) { return .rawDng }
        let stdExts: Set<String> = ["tiff", "tif", "jpeg", "jpg", "png",
                                    "heic", "heif", "bmp"]
        if stdExts.contains(ext) { return .standardImage }
        // UTI로 한 번 더 확인(확장자가 없거나 다를 때).
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let uti = CGImageSourceGetType(src) as String? {
            if uti == "com.adobe.raw" || uti == "public.dng" || uti.hasSuffix(".raw") {
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

    // MARK: RAW / DNG
    //
    // CIRAWFilter는 디지털 카메라 RAW를 16bit linear로 전개한다.
    // 기본 디폴트(노출 0, 화이트밸런스 카메라 기준)로 로드한 뒤
    // 추가 튜닝은 Chromabase 파이프라인에서 수행한다.
    static func loadRAW(_ url: URL) -> CIImage? {
        // 1) CIRAWFilter 직접 생성 시도 (DNG 포함 가장 정확한 경로).
        if let filter = CIFilter(imageURL: url, options: nil) as? CIFilter,
           let output = filter.value(forKey: kCIOutputImageKey) as? CIImage {
            return output
        }
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
}
