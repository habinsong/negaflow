import ColorSync
import CoreGraphics
import CoreImage
import CryptoKit
import Foundation

public struct DestinationGamutWarningResult: @unchecked Sendable {
    public let overlay: CGImage
    public let warningPixelCount: Int
    public let totalPixelCount: Int

    public var containsWarnings: Bool { warningPixelCount > 0 }
}

/// 선택한 출력 ICC가 재현할 수 없는 픽셀을 ColorSync의 실제 gamut-check transform으로 판정한다.
/// 채널 클리핑이나 변환 전후 RGB 차이로 근사하지 않으며, transform을 만들거나 실행하지 못하면
/// 결과를 반환하지 않는다.
public enum DestinationGamutWarning {
    private static let transformCache = GamutTransformCache()
    private static let sourceColorSpace = CGColorSpace(name: CGColorSpace.linearSRGB)!
    private static let overlayColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    public static func isSupported(for settings: SoftProofSettings) -> Bool {
        guard settings.isEnabled,
              let destinationICC = destinationICCData(for: settings) else { return false }
        return transformCache.transform(for: destinationICC) != nil
    }

    public static func makeOverlay(
        for image: CIImage,
        context: CIContext,
        settings: SoftProofSettings
    ) -> DestinationGamutWarningResult? {
        guard !Task.isCancelled,
              settings.isEnabled,
              let destinationICC = destinationICCData(for: settings),
              let cachedTransform = transformCache.transform(for: destinationICC) else {
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

        let maskBytesPerRow = (width + 7) / 8
        guard height <= Int.max / maskBytesPerRow else { return nil }
        var packedMask = [UInt8](repeating: 0, count: maskBytesPerRow * height)
        let converted = cachedTransform.withLock { transform in
            sourcePixels.withUnsafeBytes { source in
                packedMask.withUnsafeMutableBytes { destination in
                    guard let sourceAddress = source.baseAddress,
                          let destinationAddress = destination.baseAddress else { return false }
                    return ColorSyncTransformConvert(
                        transform,
                        width,
                        height,
                        destinationAddress,
                        kColorSync1BitGamut,
                        ColorSyncDataLayout(kColorSyncAlphaNone.rawValue),
                        maskBytesPerRow,
                        sourceAddress,
                        kColorSync8BitInteger,
                        ColorSyncDataLayout(kColorSyncAlphaNoneSkipLast.rawValue),
                        sourceBytesPerRow,
                        nil
                    )
                }
            }
        }
        guard converted else { return nil }
        guard !Task.isCancelled else { return nil }

        var warningCount = 0
        var overlayPixels = [UInt8](repeating: 0, count: sourceBytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width {
                let bit = UInt8(1 << (7 - (x & 7)))
                guard packedMask[y * maskBytesPerRow + x / 8] & bit != 0 else { continue }
                warningCount += 1
                let offset = y * sourceBytesPerRow + x * 4
                overlayPixels[offset] = 255
                overlayPixels[offset + 3] = 166
            }
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

private final class GamutTransformCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: LockedGamutTransform] = [:]
    private var recency: [String] = []
    private let capacity = 8

    func transform(for destinationICC: Data) -> LockedGamutTransform? {
        let key = SHA256.hash(data: destinationICC).map { String(format: "%02x", $0) }.joined()
        lock.lock()
        if let existing = entries[key] {
            touch(key)
            lock.unlock()
            return existing
        }
        lock.unlock()

        guard let created = Self.makeTransform(destinationICC: destinationICC) else { return nil }

        lock.lock()
        defer { lock.unlock() }
        if let existing = entries[key] {
            touch(key)
            return existing
        }
        entries[key] = created
        recency.append(key)
        if recency.count > capacity {
            let evicted = recency.removeFirst()
            entries.removeValue(forKey: evicted)
        }
        return created
    }

    private func touch(_ key: String) {
        recency.removeAll(where: { $0 == key })
        recency.append(key)
    }

    private static func makeTransform(destinationICC: Data) -> LockedGamutTransform? {
        guard let sourceICC = CGColorSpace(name: CGColorSpace.linearSRGB)?.copyICCData(),
              let sourceProfile = ColorSyncProfileCreate(sourceICC, nil)?.takeRetainedValue(),
              let destinationProfile = ColorSyncProfileCreate(destinationICC as CFData, nil)?.takeRetainedValue()
        else { return nil }

        let source: [CFString: Any] = [
            constant("ColorSyncProfile"): sourceProfile,
            constant("ColorSyncRenderingIntent"): constant("ColorSyncRenderingIntentRelative"),
            constant("ColorSyncTransformTag"): constant("ColorSyncTransformDeviceToPCS"),
            constant("ColorSyncBlackPointCompensation"): kCFBooleanTrue as Any,
        ]
        let destination: [CFString: Any] = [
            constant("ColorSyncProfile"): destinationProfile,
            constant("ColorSyncRenderingIntent"): constant("ColorSyncRenderingIntentRelative"),
            constant("ColorSyncTransformTag"): constant("ColorSyncTransformGamutCheck"),
            constant("ColorSyncBlackPointCompensation"): kCFBooleanTrue as Any,
        ]
        let options: [CFString: Any] = [
            constant("ColorSyncConvertQuality"): constant("ColorSyncBestQuality"),
        ]
        guard let transform = ColorSyncTransformCreate(
            [source, destination] as CFArray,
            options as CFDictionary
        )?.takeRetainedValue() else { return nil }
        return LockedGamutTransform(transform)
    }

    private static func constant(_ value: String) -> CFString {
        value as CFString
    }
}

private final class LockedGamutTransform: @unchecked Sendable {
    private let transform: ColorSyncTransform
    private let lock = NSLock()

    init(_ transform: ColorSyncTransform) {
        self.transform = transform
    }

    func withLock<T>(_ operation: (ColorSyncTransform) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation(transform)
    }
}
