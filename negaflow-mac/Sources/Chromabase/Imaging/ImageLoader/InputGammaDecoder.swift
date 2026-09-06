import Foundation
import CoreImage
import CoreGraphics

/// 색공간 변환 전의 원본 RGB 코드 값에만 감마를 적용합니다.
enum InputGammaDecoder {
    private static let context = CIContext(options: [
        .workingColorSpace: NSNull(), .outputColorSpace: NSNull(),
        .workingFormat: CIFormat.RGBAf.rawValue, .cacheIntermediates: false
    ])

    static func decode(
        _ source: CGImage,
        sourceICC: Data?,
        gamma: InputGammaInterpretation,
        maxDimension: CGFloat? = nil
    ) throws -> CIImage {
        guard let power = gamma.value else { throw InputGammaDecodeError.decodeFailed }
        try validate(source)
        let space: CGColorSpace
        if let sourceICC { space = try InputGammaProfile.linearized(sourceICC) }
        else if let linear = CGColorSpace(name: CGColorSpace.linearSRGB) { space = linear }
        else { throw InputGammaDecodeError.decodeFailed }

        var image = CIImage(cgImage: source, options: [.colorSpace: NSNull()])
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": power])
        if let maxDimension, maxDimension.isFinite, maxDimension > 0 {
            let ratio = min(1, maxDimension / max(image.extent.width, image.extent.height))
            if ratio < 1 {
                image = image.applyingFilter("CILanczosScaleTransform", parameters: [
                    kCIInputScaleKey: ratio, kCIInputAspectRatioKey: 1
                ])
            }
        }
        let width = Int(image.extent.width.rounded(.down))
        let height = Int(image.extent.height.rounded(.down))
        guard width > 0, height > 0, width <= Int.max / 16,
              height <= Int.max / (width * 16) else { throw InputGammaDecodeError.unsupportedPixels }
        let rowBytes = width * 16
        var bitmap = Data(count: rowBytes * height)
        bitmap.withUnsafeMutableBytes { bytes in
            context.render(image, toBitmap: bytes.baseAddress!, rowBytes: rowBytes,
                           bounds: CGRect(x: 0, y: 0, width: width, height: height),
                           format: .RGBAf, colorSpace: nil)
        }
        return CIImage(bitmapData: bitmap, bytesPerRow: rowBytes,
                       size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: space)
    }

    static func validate(_ source: CGImage) throws {
        guard source.colorSpace?.model == .rgb,
              [8, 16].contains(source.bitsPerComponent),
              !source.bitmapInfo.contains(.floatComponents),
              [CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(source.alphaInfo) else {
            throw InputGammaDecodeError.unsupportedPixels
        }
    }
}
