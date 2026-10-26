import Foundation
import CoreImage
import CoreGraphics
import ImageIO

extension ImageLoader {
    /// Negative film uses LibRaw camera RGB without capture WB, output tone or a color matrix.
    /// Its matrix travels separately and runs after inversion. Positive film uses Apple's
    /// scene-linear rendering; digital photos retain Apple's camera-rendered appearance.
    public enum RAWRendering: String, Codable, Sendable {
        case sceneLinear
        case cameraRendered
        case cameraNativeNegative

        /// CIRAWFilter.boostAmount. 0 = 톤 커브 없음, 1 = 디코더 기본 렌더링(Apple 기본값).
        public var boostAmount: Double {
            switch self {
            case .sceneLinear, .cameraNativeNegative: 0
            case .cameraRendered: 1
            }
        }

        /// 현상 프로세스 선택(Digital Color / Digital B&W)이 곧 디코드 의도다.
        public static func forDigitalSource(_ isDigitalSource: Bool?, filmType: FilmType? = nil) -> Self {
            if isDigitalSource == true { return .cameraRendered }
            return filmType?.requiresInversion == true ? .cameraNativeNegative : .sceneLinear
        }
    }

    static func loadRAW(
        _ url: URL,
        scaleFactor: CGFloat? = nil,
        rendering: RAWRendering = .sceneLinear
    ) -> CIImage? {
        loadRAWDecoded(url, scaleFactor: scaleFactor, rendering: rendering)?.image
    }

    static func loadRAWDecoded(
        _ url: URL,
        scaleFactor: CGFloat? = nil,
        rendering: RAWRendering = .sceneLinear
    ) -> DecodedImage? {
        if rendering == .cameraNativeNegative { return NativeCameraRAW.decode(url, scaleFactor: scaleFactor) }
        guard rawImageSourceType(of: url) != nil else { return nil }
        guard let filter = CIRAWFilter(imageURL: url) else { return nil }
        configureRAW(filter, rendering: rendering)
        if let scaleFactor {
            guard scaleFactor.isFinite, scaleFactor > 0, scaleFactor <= 1 else { return nil }
            filter.scaleFactor = Float(scaleFactor)
        }
        guard let output = filter.outputImage else { return nil }
        let decoderVersion = filter.decoderVersion.rawValue
        return DecodedImage(
            image: output,
            provenance: DecodeProvenance(
                decoder: .coreImageRAW,
                rawDecoderVersion: decoderVersion.isEmpty ? nil : decoderVersion,
                rawBoostAmount: rendering.boostAmount,
                rawScaleFactor: Double(scaleFactor ?? 1)
            )
        )
    }

    /// RAW 로드 시 추가 제어가 필요한 경우를 위한 진입점.
    /// exposureAdjustment/boost 같은 CIRAWFilter 파라미터를 노출한다.
    public static func loadRAWControlled(_ url: URL,
                                         exposureEV: Double = 0.0,
                                         boost: Double = defaultRAWBoostAmount) -> CIImage? {
        guard rawImageSourceType(of: url) != nil else { return nil }
        guard exposureEV.isFinite,
              boost.isFinite,
              (0...1).contains(boost),
              let filter = CIRAWFilter(imageURL: url) else { return nil }
        configureRAW(filter, rendering: boost == 0 ? .sceneLinear : .cameraRendered)
        filter.boostAmount = Float(boost)
        filter.exposure = Float(exposureEV)
        return filter.outputImage
    }

    private static func configureRAW(_ filter: CIRAWFilter, rendering: RAWRendering) {
        filter.boostAmount = Float(rendering.boostAmount)
        guard rendering == .sceneLinear else { return }
        filter.exposure = 0
        filter.baselineExposure = 0
        filter.shadowBias = 0
        filter.boostShadowAmount = 0
        if filter.isLocalToneMapSupported { filter.localToneMapAmount = 0 }
        filter.isGamutMappingEnabled = false
    }

}
