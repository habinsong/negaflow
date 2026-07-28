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
    public enum Decoder: String, Codable, Sendable {
        case imageIO
        case coreImageRAW
    }

    /// ICC가 없는 16-bit TIFF의 transfer function은 bit depth만으로 정할 수 없다.
    /// 호출자가 알고 있는 source role을 명시적으로 전달한다.
    public enum UntaggedTIFFRole: String, Codable, Sendable {
        case standardImage
        case linearScannerRaw
    }

    public struct DecodeProvenance: Codable, Equatable, Sendable {
        public let decoder: Decoder
        public let rawDecoderVersion: String?
        public let rawBoostAmount: Double?
        public let rawScaleFactor: Double?
        public let untaggedTIFFRole: UntaggedTIFFRole?

        public init(
            decoder: Decoder,
            rawDecoderVersion: String? = nil,
            rawBoostAmount: Double? = nil,
            rawScaleFactor: Double? = nil,
            untaggedTIFFRole: UntaggedTIFFRole? = nil
        ) {
            self.decoder = decoder
            self.rawDecoderVersion = rawDecoderVersion
            self.rawBoostAmount = rawBoostAmount
            self.rawScaleFactor = rawScaleFactor
            self.untaggedTIFFRole = untaggedTIFFRole
        }
    }

    public struct DecodedImage {
        public let image: CIImage
        public let provenance: DecodeProvenance

        public init(image: CIImage, provenance: DecodeProvenance) {
            self.image = image
            self.provenance = provenance
        }
    }

    /// Apple CIRAWFilter의 기본 1.0은 full global tone curve다. negaflow source decode는
    /// develop 단계 전 linear response를 유지하므로 0.0을 명시한다.
    public static let defaultRAWBoostAmount = 0.0

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
            if isRawImageSourceType(uti) {
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
    ///   • 프로필 없는 16bit+   → linear gamma 1.0(스캐너 raw)로 해석한다. 색관리 소프트웨어는
    ///     TIFF                  16bit 출력에 프로필을 붙이므로, 프로필 없는 16bit TIFF는 스캐너
    ///                           소프트웨어의 raw 출력이다. 값 도메인을 틀리면 반전이 무너진다
    ///                           (실측: 같은 파일을 sRGB로 읽으면 Dmin 실측이 실패하고 결과가 흰색으로 붕뜬다).
    ///                           IT8 차트처럼 일반 이미지로 읽어야 하는 호출자는 `.standardImage`를 명시한다.
    ///   • 그 외                → CGImage가 제공한 색공간을 그대로 사용한다.
    ///
    /// 근거: VueScan raw는 16bit에서 linear(gamma 1.0), 8bit에서 gamma 2.2. SilverFast HDRi는
    /// linear 이며 스캐너 디바이스 프로필을 임베드한다.
    public static func loadImported(
        _ url: URL,
        untaggedTIFFRole: UntaggedTIFFRole = .linearScannerRaw
    ) -> CIImage? {
        loadImportedDecoded(url, untaggedTIFFRole: untaggedTIFFRole)?.image
    }

    public static func loadImportedDecoded(
        _ url: URL,
        untaggedTIFFRole: UntaggedTIFFRole = .linearScannerRaw
    ) -> DecodedImage? {
        // RAW/DNG는 CIRAWFilter가 파일 orientation을 기본 적용하므로 여기서 재적용하지 않는다.
        if kind(of: url) == .rawDng { return loadRAWDecoded(url) }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            guard let image = loadStandard(url) else { return nil }
            return DecodedImage(
                image: image,
                provenance: DecodeProvenance(decoder: .imageIO)
            )
        }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let base = profileAwareImage(
            cg,
            properties: props,
            untaggedTIFFRole: untaggedTIFFRole
        )
        // CGImageSourceCreateImageAtIndex는 orientation을 적용하지 않는다 → EXIF orientation을 반영해
        // 세로/회전 사진을 정립시킨다(프리뷰 썸네일은 WithTransform으로 이미 정립 — 방향 일치).
        let exif = exifOrientation(props)
        let image = exif == 1 ? base : base.oriented(forExifOrientation: exif)
        return DecodedImage(
            image: image,
            provenance: DecodeProvenance(
                decoder: .imageIO,
                untaggedTIFFRole: untaggedTIFFRoleIfApplicable(
                    cg,
                    properties: props,
                    requestedRole: untaggedTIFFRole
                )
            )
        )
    }

    public static func loadScannerPreview(_ url: URL, maxDimension: CGFloat,
                                          highResolutionThreshold: CGFloat) -> PreviewImage? {
        guard maxDimension > 0,
              let src = imageSource(url),
              let size = sourcePixelSize(src),
              max(size.width, size.height) > highResolutionThreshold,
              max(size.width, size.height) > maxDimension,
              let cg = thumbnail(from: src, maxDimension: maxDimension, applyOrientation: false) else {
            return nil
        }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        // 16bit 입력은 ICC 유무와 무관하게 linear 16bit 프록시로 materialize한다. 임베디드
        // ICC 변환은 profileAwareImage가 담당하며, 이 플래그는 프록시 저장 정밀도를 뜻한다.
        let usesLinearSRGB = sourceBitDepth(cg, properties: props) >= 16
        return PreviewImage(
            image: profileAwareImage(
                cg,
                properties: props,
                untaggedTIFFRole: .linearScannerRaw
            ),
            sourcePixelSize: size,
            usesLinearSRGB: usesLinearSRGB
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
        guard let cg = thumbnail(from: src, maxDimension: maxDimension, applyOrientation: true) else { return nil }
        let usesLinearSRGB = sourceBitDepth(cg, properties: props) >= 16
        return PreviewImage(
            // 프록시는 전체 해상도 로더와 같은 규칙으로 읽어야 한다. 규칙이 갈리면 프리뷰와
            // 최종 렌더가 다른 이미지가 된다.
            image: profileAwareImage(
                cg,
                properties: props,
                untaggedTIFFRole: .linearScannerRaw
            ),
            sourcePixelSize: size,
            usesLinearSRGB: usesLinearSRGB
        )
    }

    // MARK: standard (TIFF/JPEG/PNG/...)
}
