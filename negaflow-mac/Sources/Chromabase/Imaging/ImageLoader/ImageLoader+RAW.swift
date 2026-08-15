import Foundation
import CoreImage
import CoreGraphics
import ImageIO

extension ImageLoader {
    /// RAW 디코드가 어떤 도메인의 값을 내놓아야 하는가.
    ///
    /// 같은 CIRAWFilter 라도 두 소비자의 요구가 정반대다.
    ///   • 필름 스캐너 raw DNG(VueScan/SilverFast) → **linear**. 네거티브 반전은 Dmin 을
    ///     투과율로 재므로 톤 커브가 끼면 반전이 무너진다.
    ///   • 디지털 카메라 RAW → **카메라 렌더링**. 뒤따르는 포지티브 파이프라인은 패스스루라
    ///     여기서 렌더링하지 않으면 장면 linear 값이 그대로 표시 도메인으로 나가
    ///     어둡고 밋밋해진다(실측: 8개 포맷 52장에서 RMS 대비 −20~−38%, 명부 소멸).
    public enum RAWRendering: String, Codable, Sendable {
        case sceneLinear
        case cameraRendered

        /// CIRAWFilter.boostAmount. 0 = 톤 커브 없음, 1 = 디코더 기본 렌더링(Apple 기본값).
        public var boostAmount: Double {
            switch self {
            case .sceneLinear: 0
            case .cameraRendered: 1
            }
        }

        /// 현상 프로세스 선택(Digital Color / Digital B&W)이 곧 디코드 의도다.
        public static func forDigitalSource(_ isDigitalSource: Bool?) -> Self {
            isDigitalSource == true ? .cameraRendered : .sceneLinear
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
        guard rawImageSourceType(of: url) != nil else { return nil }
        guard let filter = CIRAWFilter(imageURL: url) else { return nil }
        filter.boostAmount = Float(rendering.boostAmount)
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
        filter.boostAmount = Float(boost)
        filter.exposure = Float(exposureEV)
        return filter.outputImage
    }

}
