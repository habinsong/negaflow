import CoreGraphics
import CoreImage

enum ExportRenderedImage {
    static func make(
        _ image: CIImage,
        using context: CIContext,
        colorSpace: CGColorSpace,
        bitDepth: ExportBitDepth,
        preserveAlpha: Bool,
        appliesDither: Bool
    ) -> CGImage? {
        let input = appliesDither ? OutputDither.apply(to: image) : image
        let format: CIFormat = bitDepth == .sixteen ? .RGBA16 : .RGBA8
        guard let rendered = context.createCGImage(
            input,
            from: image.extent,
            format: format,
            colorSpace: colorSpace
        ) else {
            return nil
        }
        return preserveAlpha ? rendered : droppingAlpha(from: rendered)
    }

    private static func droppingAlpha(from image: CGImage) -> CGImage? {
        guard let provider = image.dataProvider else { return nil }
        let alphaMask = CGBitmapInfo.alphaInfoMask.rawValue
        let baseInfo = image.bitmapInfo.rawValue & ~alphaMask
        let bitmapInfo = CGBitmapInfo(
            rawValue: baseInfo | CGImageAlphaInfo.noneSkipLast.rawValue
        )
        return CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: image.bitsPerComponent,
            bitsPerPixel: image.bitsPerPixel,
            bytesPerRow: image.bytesPerRow,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: image.decode,
            shouldInterpolate: image.shouldInterpolate,
            intent: image.renderingIntent
        )
    }
}
