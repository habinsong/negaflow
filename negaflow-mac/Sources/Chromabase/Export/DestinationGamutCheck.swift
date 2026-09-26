import ColorSync
import CoreGraphics
import CryptoKit
import Foundation

/// 대상 ICC의 gamut 판정을 픽셀당 1바이트(0 = 재현 가능, 1 = 재현 불가) 마스크로 돌려준다.
///
/// ColorSync의 gamut-check 동작은 OS마다 다르다. macOS 26까지는 1-bit 묶음으로 썼지만, 실측한
/// macOS 27은 행렬형 RGB 대상(sRGB·Display P3·보정 RGB)의 gamut-check 변환을 거부하고, LUT형
/// 대상은 1-bit를 요청해도 픽셀당 4바이트를 써서 1-bit 크기 버퍼를 넘친다. 그래서 transform마다
/// 한 번 넉넉한 감시 버퍼로 실제 기록 크기를 재서 안전한 방식만 고른다.
final class DestinationGamutCheck: @unchecked Sendable {
    enum Mode: Equatable {
        /// 행당 (width + 7) / 8 바이트의 1-bit 묶음(macOS 26까지의 동작).
        case packedBits
        /// gamut-check 변환의 8-bit 출력, 픽셀당 1바이트.
        case bytePerPixel
        /// 행렬형 RGB 대상: 자르지 않은 장치 RGB가 [0, 1]을 벗어나면 재현 불가. 행렬형 대상의
        /// gamut은 정확히 장치 RGB 큐브이므로 근사가 아니다.
        case deviceRange
    }

    /// 장치 값 1/512(8-bit 한 단계의 절반) 이내의 넘침은 부동소수 반올림으로 본다. 같은
    /// profile끼리의 경계색이 거짓 경고가 되지 않게 한다.
    static let deviceRangeTolerance: Float = 1.0 / 512.0

    let mode: Mode
    private let transform: ColorSyncTransform
    private let lock = NSLock()

    private init(mode: Mode, transform: ColorSyncTransform) {
        self.mode = mode
        self.transform = transform
    }

    /// `rgbx`는 선형 sRGB 8-bit RGBX. 반환 배열 길이는 width × height.
    func outOfGamutMask(rgbx: [UInt8], width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0, rgbx.count == width * height * 4 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        switch mode {
        case .packedBits: return packedBitsMask(rgbx: rgbx, width: width, height: height)
        case .bytePerPixel: return bytePerPixelMask(rgbx: rgbx, width: width, height: height)
        case .deviceRange: return deviceRangeMask(rgbx: rgbx, width: width, height: height)
        }
    }

    private func packedBitsMask(rgbx: [UInt8], width: Int, height: Int) -> [UInt8]? {
        let rowBytes = (width + 7) / 8
        var packed = [UInt8](repeating: 0, count: rowBytes * height)
        guard Self.convert(transform, rgbx: rgbx, width: width, height: height,
                           into: &packed, depth: kColorSync1BitGamut,
                           layout: kColorSyncAlphaNone, rowBytes: rowBytes) else { return nil }
        var mask = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width where packed[y * rowBytes + x / 8] & UInt8(1 << (7 - (x & 7))) != 0 {
                mask[y * width + x] = 1
            }
        }
        return mask
    }

    private func bytePerPixelMask(rgbx: [UInt8], width: Int, height: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: width * height)
        guard Self.convert(transform, rgbx: rgbx, width: width, height: height,
                           into: &bytes, depth: kColorSync8BitInteger,
                           layout: kColorSyncAlphaNone, rowBytes: width) else { return nil }
        return bytes.map { $0 == 0 ? 0 : 1 }
    }

    /// 큰 미리보기에서 float 버퍼가 커지지 않도록 띠 단위로 변환한다.
    private func deviceRangeMask(rgbx: [UInt8], width: Int, height: Int) -> [UInt8]? {
        let bandRows = max(1, min(height, 65_536 / width))
        var mask = [UInt8](repeating: 0, count: width * height)
        var device = [Float](repeating: 0, count: bandRows * width * 3)
        let lower = -Self.deviceRangeTolerance
        let upper = 1 + Self.deviceRangeTolerance
        var y = 0
        while y < height {
            let rows = min(bandRows, height - y)
            let band = Array(rgbx[(y * width * 4)..<((y + rows) * width * 4)])
            guard Self.convert(transform, rgbx: band, width: width, height: rows,
                               into: &device, depth: kColorSync32BitFloat,
                               layout: kColorSyncAlphaNone, rowBytes: width * 12) else { return nil }
            for index in 0..<(rows * width) {
                let r = device[index * 3], g = device[index * 3 + 1], b = device[index * 3 + 2]
                if r < lower || r > upper || g < lower || g > upper || b < lower || b > upper {
                    mask[y * width + index] = 1
                }
            }
            y += rows
        }
        return mask
    }

    private static func convert<Element>(
        _ transform: ColorSyncTransform,
        rgbx: [UInt8],
        width: Int,
        height: Int,
        into destination: inout [Element],
        depth: ColorSyncDataDepth,
        layout: ColorSyncAlphaInfo,
        rowBytes: Int
    ) -> Bool {
        rgbx.withUnsafeBytes { source in
            destination.withUnsafeMutableBytes { output in
                guard let sourceAddress = source.baseAddress,
                      let outputAddress = output.baseAddress,
                      output.count >= rowBytes * height else { return false }
                return ColorSyncTransformConvert(
                    transform, width, height,
                    outputAddress, depth, ColorSyncDataLayout(layout.rawValue), rowBytes,
                    sourceAddress, kColorSync8BitInteger,
                    ColorSyncDataLayout(kColorSyncAlphaNoneSkipLast.rawValue), width * 4,
                    nil
                )
            }
        }
    }
}

// MARK: - 생성과 보정

extension DestinationGamutCheck {
    static func make(destinationICC: Data) -> DestinationGamutCheck? {
        guard let sourceICC = CGColorSpace(name: CGColorSpace.linearSRGB)?.copyICCData(),
              let sourceProfile = ColorSyncProfileCreate(sourceICC, nil)?.takeRetainedValue(),
              let destinationProfile = ColorSyncProfileCreate(destinationICC as CFData, nil)?.takeRetainedValue()
        else { return nil }

        if let gamut = transform(from: sourceProfile, to: destinationProfile,
                                 tag: "ColorSyncTransformGamutCheck") {
            if writesOnlyWithin(gamut, depth: kColorSync1BitGamut, rowBytes: 1, expectedBytes: 1) {
                return DestinationGamutCheck(mode: .packedBits, transform: gamut)
            }
            if writesOnlyWithin(gamut, depth: kColorSync8BitInteger,
                                rowBytes: calibrationWidth, expectedBytes: calibrationWidth) {
                return DestinationGamutCheck(mode: .bytePerPixel, transform: gamut)
            }
        }
        guard isMatrixRGB(destinationProfile),
              let device = transform(from: sourceProfile, to: destinationProfile,
                                     tag: "ColorSyncTransformPCSToDevice"),
              writesOnlyWithin(device, depth: kColorSync32BitFloat,
                               rowBytes: calibrationWidth * 12,
                               expectedBytes: calibrationWidth * 12) else { return nil }
        return DestinationGamutCheck(mode: .deviceRange, transform: device)
    }

    private static func transform(
        from source: ColorSyncProfile,
        to destination: ColorSyncProfile,
        tag: String
    ) -> ColorSyncTransform? {
        let sourceStep: [CFString: Any] = [
            key("ColorSyncProfile"): source,
            key("ColorSyncRenderingIntent"): key("ColorSyncRenderingIntentRelative"),
            key("ColorSyncTransformTag"): key("ColorSyncTransformDeviceToPCS"),
            key("ColorSyncBlackPointCompensation"): kCFBooleanTrue as Any,
        ]
        let destinationStep: [CFString: Any] = [
            key("ColorSyncProfile"): destination,
            key("ColorSyncRenderingIntent"): key("ColorSyncRenderingIntentRelative"),
            key("ColorSyncTransformTag"): key(tag),
            key("ColorSyncBlackPointCompensation"): kCFBooleanTrue as Any,
        ]
        let options: [CFString: Any] = [
            key("ColorSyncConvertQuality"): key("ColorSyncBestQuality"),
        ]
        return ColorSyncTransformCreate(
            [sourceStep, destinationStep] as CFArray,
            options as CFDictionary
        )?.takeRetainedValue()
    }

    /// 상대 색도 의도에서 ColorSync가 행렬·TRC로 변환하는 RGB 대상인지. B2A LUT가 있으면
    /// 그쪽이 우선하고 출력이 [0, 1]에 묶이므로 범위 판정을 쓸 수 없다.
    private static func isMatrixRGB(_ profile: ColorSyncProfile) -> Bool {
        let required = ["rXYZ", "gXYZ", "bXYZ", "rTRC", "gTRC", "bTRC"]
        let lookupTables = ["B2A0", "B2A1", "B2A2"]
        return required.allSatisfy { ColorSyncProfileContainsTag(profile, $0 as CFString) }
            && !lookupTables.contains { ColorSyncProfileContainsTag(profile, $0 as CFString) }
    }

    private static let calibrationWidth = 8

    /// 재현 가능·불가능 색을 섞은 한 줄. 넉넉한 버퍼 두 벌(서로 다른 감시값)에 변환해,
    /// 요청한 크기 밖을 한 바이트라도 건드리면 그 방식은 쓰지 않는다.
    private static func writesOnlyWithin(
        _ transform: ColorSyncTransform,
        depth: ColorSyncDataDepth,
        rowBytes: Int,
        expectedBytes: Int
    ) -> Bool {
        let pixels: [UInt8] = [
            128, 128, 128, 255, 1, 1, 1, 255, 254, 254, 254, 255, 254, 1, 1, 255,
            1, 254, 1, 255, 1, 1, 254, 255, 200, 30, 30, 255, 30, 200, 30, 255,
        ]
        let capacity = 4_096
        for sentinel: UInt8 in [0xA5, 0x5A] {
            var buffer = [UInt8](repeating: sentinel, count: capacity)
            let converted = pixels.withUnsafeBytes { source in
                buffer.withUnsafeMutableBytes { output in
                    ColorSyncTransformConvert(
                        transform, calibrationWidth, 1,
                        output.baseAddress!, depth, ColorSyncDataLayout(kColorSyncAlphaNone.rawValue), rowBytes,
                        source.baseAddress!, kColorSync8BitInteger,
                        ColorSyncDataLayout(kColorSyncAlphaNoneSkipLast.rawValue), calibrationWidth * 4,
                        nil
                    )
                }
            }
            guard converted, buffer[expectedBytes...].allSatisfy({ $0 == sentinel }) else { return false }
        }
        return true
    }

    /// ColorSync 키 상수는 SDK에서 전역 `var`라 strict concurrency가 참조를 막는다. 값이 이름과
    /// 같은 문자열이므로 그대로 쓴다.
    private static func key(_ value: String) -> CFString {
        value as CFString
    }
}

// MARK: - Cache

final class DestinationGamutCheckCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: DestinationGamutCheck] = [:]
    private var recency: [String] = []
    private let capacity = 8

    func check(for destinationICC: Data) -> DestinationGamutCheck? {
        let key = SHA256.hash(data: destinationICC).map { String(format: "%02x", $0) }.joined()
        lock.lock()
        if let existing = entries[key] {
            touch(key)
            lock.unlock()
            return existing
        }
        lock.unlock()

        guard let created = DestinationGamutCheck.make(destinationICC: destinationICC) else { return nil }

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
}
