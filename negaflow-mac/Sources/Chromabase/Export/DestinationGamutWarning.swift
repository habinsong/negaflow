import CoreGraphics
import CoreImage
import Foundation

public struct DestinationGamutWarningResult: @unchecked Sendable {
    public let overlay: CGImage
    public let warningPixelCount: Int
    public let totalPixelCount: Int

    public var containsWarnings: Bool { warningPixelCount > 0 }
}

/// 선택한 출력 ICC가 재현할 수 없는 픽셀을 판정한다. ColorSync의 gamut-check transform을 쓰고,
/// 그것이 거부되는 행렬형 RGB 대상(macOS 27)은 자르지 않은 장치 RGB의 [0, 1] 이탈로 판정한다 —
/// 행렬형 대상의 gamut은 정확히 장치 RGB 큐브라 근사가 아니다(`DestinationGamutCheck`).
/// 채널 클리핑이나 변환 전후 RGB 차이로 근사하지 않으며, 판정 방법을 세우지 못하면 결과를
/// 반환하지 않는다.
public enum DestinationGamutWarning {
    private static let checkCache = DestinationGamutCheckCache()
    private static let sourceColorSpace = CGColorSpace(name: CGColorSpace.linearSRGB)!
    private static let overlayColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    public static func isSupported(for settings: SoftProofSettings) -> Bool {
        guard settings.isEnabled,
              let destinationICC = destinationICCData(for: settings) else { return false }
        return checkCache.check(for: destinationICC) != nil
    }

    public static func makeOverlay(
        for image: CIImage,
        context: CIContext,
        settings: SoftProofSettings
    ) -> DestinationGamutWarningResult? {
        guard !Task.isCancelled,
              settings.isEnabled,
              let destinationICC = destinationICCData(for: settings),
              let gamutCheck = checkCache.check(for: destinationICC) else {
            return nil
        }

        let bounds = image.extent.integral
        let width = Int(bounds.width)
        let height = Int(bounds.height)
        guard width > 0, height > 0,
              width <= Int.max / 4,
              height <= Int.max / (width * 4) else { return nil }

        let sourceBytesPerRow = width * 4
        var sourcePixels = [UInt8](repeating: 0, count: sourceBytesPerRow * height)
        context.render(
            image,
            toBitmap: &sourcePixels,
            rowBytes: sourceBytesPerRow,
            bounds: bounds,
            format: .RGBA8,
            colorSpace: sourceColorSpace
        )
        guard !Task.isCancelled else { return nil }

        // ColorSync는 같은 RGB gamut의 수학적 경계(정확한 0/255)를 반올림 때문에 바깥으로
        // 판정할 수 있다. 판정 전용 버퍼만 1 LSB 안쪽으로 넣어 동일-profile 거짓 경고를 막는다.
        // 표시·현상·내보내기 픽셀은 변경하지 않는다.
        for offset in stride(from: 0, to: sourcePixels.count, by: 4) {
            sourcePixels[offset] = min(max(sourcePixels[offset], 1), 254)
            sourcePixels[offset + 1] = min(max(sourcePixels[offset + 1], 1), 254)
            sourcePixels[offset + 2] = min(max(sourcePixels[offset + 2], 1), 254)
            sourcePixels[offset + 3] = 255
        }

        guard let outOfGamut = gamutCheck.outOfGamutMask(
            rgbx: sourcePixels,
            width: width,
            height: height
        ) else { return nil }
        guard !Task.isCancelled else { return nil }

        var warningCount = 0
        var overlayPixels = [UInt8](repeating: 0, count: sourceBytesPerRow * height)
        for index in 0..<(width * height) where outOfGamut[index] != 0 {
            warningCount += 1
            overlayPixels[index * 4] = 255
            overlayPixels[index * 4 + 3] = 166
        }

        guard let provider = CGDataProvider(data: Data(overlayPixels) as CFData),
              let overlay = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: sourceBytesPerRow,
                  space: overlayColorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else { return nil }

        return DestinationGamutWarningResult(
            overlay: overlay,
            warningPixelCount: warningCount,
            totalPixelCount: width * height
        )
    }

    private static func destinationICCData(for settings: SoftProofSettings) -> Data? {
        if let custom = settings.iccProfileData {
            guard SoftProof.rgbOutputColorSpace(fromICCData: custom) != nil else { return nil }
            return custom
        }
        return SoftProof.profile(for: settings.colorSpace)?.iccData
    }
}
