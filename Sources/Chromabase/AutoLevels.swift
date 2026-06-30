import Foundation
import CoreImage
import CoreGraphics

// MARK: - AutoLevels (SANE raw 데이터 보정)
//
// 근본 원인(실측):
//   SANE genesys 백엔드는 감마/노출 보정 없이 raw 데이터를 내보낸다.
//   슬라이드 스캔에서 전체 픽셀의 97.8%가 0~74(8bit 정규화)에만 몰려 있고,
//   128 이상 픽셀이 0개였다. SilverFast는 자체 소프트웨어로 이를 보정하지만
//   SANE은 안 한다. 따라서 Chromabase가 raw 직후 단계에서 자동으로
//   백/블랙포인트를 검출해 데이터를 정상 범위(0~1)로 펴야 한다.
//
// 알고리즘:
//   1. 이미지를 작게(예: 256×N) 다운샘플링하여 히스토그램 샘플링
//   2. 채널별로 p0.5(블랙포인트)와 p99.9(백포인트) 검출
//   3. (x - black) / (white - black) 으로 스트레치 → clamp
//
// 입력이 이미 정상 범위(0~255 골고루)면 보정량이 거의 0이 되어 무해하다.
public enum AutoLevels {
    /// 이미지의 실제 데이터 범위를 자동 검출하여 0~1 선형으로 스트레치.
    /// - Parameters:
    ///   - blackClip: 블랙포인트로 사용할 하위 백분위(기본 0.5%)
    ///   - whiteClip: 화이트포인트로 사용할 상위 백분위(기본 0.1%)
    public static func apply(to image: CIImage,
                             blackClip: Double = 0.005,
                             whiteClip: Double = 0.001,
                             sampleColorSpace: CGColorSpace? = nil,
                             outputWhite outputWhiteOverride: Double? = nil,
                             outputBlack: Double = 0.0) -> CIImage {
        // 샘플링을 위해 작은 영역으로 축소(CIAreaAverage 로는 히스토그램이 안 나옴).
        // 대신 작은 축소본을 렌더링해서 픽셀을 직접 읽는다.
        guard let (black, white) = sampleBlackWhite(
            image,
            blackClip: blackClip,
            whiteClip: whiteClip,
            sampleColorSpace: sampleColorSpace
        ) else {
            return image   // 샘플링 실패 시 원본 반환(무해)
        }
        // 의미 있는 보정인지 검사(이미 펴져 있으면 건너뛴다 — 무해성).
        let whiteR = white.x, whiteG = white.y, whiteB = white.z
        let blackR = black.x, blackG = black.y, blackB = black.z
        let minimumRange = 0.04
        let maximumRange = max(whiteR - blackR, max(whiteG - blackG, whiteB - blackB))
        guard maximumRange >= minimumRange else { return image }
        // white 가 이미 0.95 이상이고 black 이 0.05 이하면 보정 불필요.
        if whiteR > 0.95 && whiteG > 0.95 && whiteB > 0.95 &&
           blackR < 0.05 && blackG < 0.05 && blackB < 0.05 {
            return image
        }

        // CIColorMatrix + CIColorControls 로 per-channel 스트레치를 근사.
        // out = (in - black) / (white - black)
        //   = in * (1/(white-black)) + (-black/(white-black))
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)
        let outputWhite = outputWhiteOverride ?? (sampleColorSpace?.name == linear?.name ? 0.70 : 0.88)
        // out = outputBlack + (in - black) * (outputWhite - outputBlack) / range.
        // outputBlack > 0이면 가장 어두운 값을 0이 아니라 작은 floor로 보내 암부 계조를
        // 남긴다(슬라이드 암부 뭉개짐 방지). 네거티브는 기본 0이라 동작이 그대로다.
        func transform(_ black: Double, _ white: Double) -> (scale: Double, bias: Double) {
            let range = white - black
            guard range >= minimumRange else { return (1, 0) }
            let scale = (outputWhite - outputBlack) / range
            return (scale, outputBlack - black * scale)
        }
        let red = transform(blackR, whiteR)
        let green = transform(blackG, whiteG)
        let blue = transform(blackB, whiteB)

        var stretched = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(red.scale), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(green.scale), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(blue.scale), w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: CGFloat(red.bias), y: CGFloat(green.bias),
                                        z: CGFloat(blue.bias), w: 0),
        ])
        stretched = stretched.applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
        ])
        return stretched.cropped(to: image.extent)
    }

    /// 작은 축소본을 렌더링해서 채널별 black/white 포인트(p백분위) 검출.
    static func sampleBlackWhite(_ image: CIImage,
                                 blackClip: Double,
                                 whiteClip: Double,
                                 sampleColorSpace: CGColorSpace? = nil)
        -> (black: SIMD3<Double>, white: SIMD3<Double>)? {
        let extent = image.extent
        guard extent.width > 4, extent.height > 4 else { return nil }

        // 256px 폭으로 축소(히스토그램 샘플링용 — 품질은 중요하지 않다).
        let targetW = 256
        let scale = Double(targetW) / extent.width
        let targetH = max(1, Int(extent.height * scale))
        let scaled = image.transformed(by: CGAffineTransform(
            scaleX: CGFloat(scale), y: CGFloat(scale)))

        let cs = sampleColorSpace
            ?? CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        var bitmap = [Float](repeating: 0, count: targetW * targetH * 4)
        let ciCtx = SamplingContextPool.context(workingColorSpace: cs)
        ciCtx.render(scaled, toBitmap: &bitmap,
                     rowBytes: targetW * 4 * MemoryLayout<Float>.size,
                     bounds: CGRect(x: 0, y: 0, width: targetW, height: targetH),
                     format: .RGBAf, colorSpace: cs)

        let n = targetW * targetH
        var rVals = [Double](repeating: 0, count: n)
        var gVals = [Double](repeating: 0, count: n)
        var bVals = [Double](repeating: 0, count: n)
        for i in 0..<n {
            rVals[i] = Double(bitmap[i*4])
            gVals[i] = Double(bitmap[i*4 + 1])
            bVals[i] = Double(bitmap[i*4 + 2])
        }
        _ = scaled
        rVals.sort(); gVals.sort(); bVals.sort()

        let p = { (sorted: [Double], pct: Double) -> Double in
            let idx = max(0, min(sorted.count - 1, Int(Double(sorted.count) * pct)))
            return sorted[idx]
        }
        let black = SIMD3(p(rVals, blackClip), p(gVals, blackClip), p(bVals, blackClip))
        let white = SIMD3(p(rVals, 1.0 - whiteClip), p(gVals, 1.0 - whiteClip), p(bVals, 1.0 - whiteClip))
        return (black, white)
    }
}
