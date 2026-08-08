import Foundation
import CoreImage
import CoreGraphics
import ImageIO

extension ImageLoader {
    static func loadRAW(_ url: URL, scaleFactor: CGFloat? = nil) -> CIImage? {
        loadRAWDecoded(url, scaleFactor: scaleFactor)?.image
    }

    static func loadRAWDecoded(
        _ url: URL,
        scaleFactor: CGFloat? = nil
    ) -> DecodedImage? {
        guard rawImageSourceType(of: url) != nil else { return nil }
        guard let filter = CIRAWFilter(imageURL: url) else { return nil }
        filter.boostAmount = Float(defaultRAWBoostAmount)
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
                rawBoostAmount: defaultRAWBoostAmount,
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
