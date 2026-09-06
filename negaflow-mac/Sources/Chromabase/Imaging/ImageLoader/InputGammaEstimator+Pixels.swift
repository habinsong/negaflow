import CoreGraphics
import Foundation

extension InputGammaEstimator {
    /// ImageIO가 풀어 준 RGB 코드 값을 색변환·축소 없이 읽습니다. 표본만 작게 보관합니다.
    static func estimate(_ image: CGImage) -> Estimate? {
        guard (try? InputGammaDecoder.validate(image)) != nil,
              [24, 32, 48, 64].contains(image.bitsPerPixel),
              let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data),
              image.height <= CFDataGetLength(data) / max(1, image.bytesPerRow) else { return nil }
        let stride = image.bitsPerPixel / 8
        let componentBytes = image.bitsPerComponent / 8
        let skip = image.alphaInfo == .noneSkipFirst ? 1 : 0
        let order = image.bitmapInfo.intersection(.byteOrderMask)
        let reversed = componentBytes == 1 && stride == 4 && order == .byteOrder32Little
        let little = order == .byteOrder16Little
        guard stride / componentBytes >= 3 + skip, image.width <= image.bytesPerRow / stride else { return nil }
        let edges = sample(width: image.width, height: image.height) { x, y in
            var pixel = SIMD3<Double>()
            for channel in 0..<3 {
                let component = reversed ? 3 - (channel + skip) : channel + skip
                let offset = y * image.bytesPerRow + x * stride + component * componentBytes
                if componentBytes == 1 { pixel[channel] = Double(bytes[offset]) / 255 }
                else {
                    let high = bytes[offset + (little ? 1 : 0)], low = bytes[offset + (little ? 0 : 1)]
                    pixel[channel] = Double(Int(high) * 256 + Int(low)) / 65535
                }
            }
            return pixel
        }
        return estimate(edges)
    }
}
