import CoreGraphics
import CoreImage
import Foundation
@testable import Chromabase

// 노출·화이트밸런스·측정 영역 테스트가 함께 쓰는 합성 float 픽스처. 실사진은 쓰지 않는다.
// 좌표는 bitmapData 행 순서(y-down)와 CI 좌표(y-up)가 상하 대칭인 배치로 잡아 혼동을 없앤다.
enum SyntheticScan {
    static let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    /// 오렌지 마스크형 컬러 네거티브 베이스 투과율.
    static let colorBase = SIMD3<Double>(0.80, 0.55, 0.35)
    static let neutralBase = SIMD3<Double>(0.80, 0.80, 0.80)

    /// 중립 밀도 웨지(가로 패치). 패치 k 의 베이스 위 밀도 = offset + (maxDensity − offset)·k/(n−1).
    struct Wedge {
        let image: CIImage
        let width: Int
        let height: Int
        let patchCenters: [Int]
    }

    static func negativeWedge(base: SIMD3<Double> = colorBase,
                              patchCount: Int = 21,
                              maxDensity: Double = 1.55,
                              offset: Double = 0) -> Wedge {
        let patchW = 60, margin = 70, height = 160
        let width = patchCount * patchW + margin * 2
        func density(_ k: Int) -> Double {
            offset + (maxDensity - offset) * Double(k) / Double(patchCount - 1)
        }
        let image = makeImage(width: width, height: height) { x, _ in
            let k = (x < margin || x >= width - margin) ? patchCount / 2 : (x - margin) / patchW
            return base * pow(10, -density(k))
        }
        let centers = (0..<patchCount).map { margin + $0 * patchW + patchW / 2 }
        return Wedge(image: image, width: width, height: height, patchCenters: centers)
    }

    static func makeImage(width: Int, height: Int,
                          _ pixel: (Int, Int) -> SIMD3<Double>) -> CIImage {
        var px = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v = pixel(x, y)
                let i = (y * width + x) * 4
                px[i] = Float(v.x); px[i + 1] = Float(v.y); px[i + 2] = Float(v.z); px[i + 3] = 1
            }
        }
        return CIImage(bitmapData: px.withUnsafeBufferPointer { Data(buffer: $0) },
                       bytesPerRow: width * 16,
                       size: CGSize(width: width, height: height),
                       format: .RGBAf, colorSpace: linear)
    }

    /// 각 패치 중앙 20×40 영역의 linear 평균.
    static func patchMeans(_ image: CIImage, wedge: Wedge,
                           context: CIContext = ChromabaseEngine.sharedLinearRenderContext) -> [SIMD3<Double>] {
        let w = wedge.width, h = wedge.height
        var bmp = [Float](repeating: 0, count: w * h * 4)
        context.render(image, toBitmap: &bmp, rowBytes: w * 16,
                       bounds: CGRect(x: 0, y: 0, width: w, height: h),
                       format: .RGBAf, colorSpace: linear)
        return wedge.patchCenters.map { cx in
            var sum = SIMD3<Double>(repeating: 0)
            var n = 0.0
            for y in (h / 2 - 20)..<(h / 2 + 20) {
                for x in (cx - 10)..<(cx + 10) {
                    let i = (y * w + x) * 4
                    sum += SIMD3(Double(bmp[i]), Double(bmp[i + 1]), Double(bmp[i + 2]))
                    n += 1
                }
            }
            return sum / n
        }
    }

    /// 수동 베이스로 현상한 뒤 표시 경계(DisplayGamutMap)까지 거친 패치 평균.
    static func developedDisplayPatches(_ wedge: Wedge, base: SIMD3<Double> = colorBase,
                                        context: CIContext = ChromabaseEngine.sharedLinearRenderContext,
                                        _ configure: (inout DevelopParameters) -> Void = { _ in }) -> [SIMD3<Double>] {
        var params = DevelopParameters()
        params.baseEstimationMode = .manual
        params.manualBaseRGB = base
        configure(&params)
        let developed = ChromabaseEngine().developScanner(
            image: wedge.image, base: FilmBase(rgb: base, source: .manual), params: params
        )
        return patchMeans(DisplayGamutMap.apply(to: developed), wedge: wedge, context: context)
    }

    static func luma(_ c: SIMD3<Double>) -> Double {
        0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
    }

    /// linear 값 → 8bit sRGB 코드.
    static func code(_ v: Double) -> Int {
        let x = min(max(v, 0), 1)
        let e = x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
        return Int((e * 255).rounded())
    }
}

// MARK: - 디지털 카메라 스캔형 프레임

/// 필름보다 넓게 찍힌 카메라 스캔: 백라이트 → 홀더 → 리베이트(베이스) → 사진 영역(중립 웨지) +
/// 좌우 이웃 프레임. 2026-10-14 측정 영역·베이스 검출 수정의 회귀 픽스처.
struct CameraScanFrame {
    enum Rebate { case full, betweenFramesOnly, hidden }

    static let width = 1500, height = 1000
    static let imageX = 140..<1360, imageY = 170..<830          // bitmap 행(y-down)
    static let patchCount = 21
    static var patchWidth: Int { imageX.count / patchCount }
    /// Portra 400 데이터시트 Dmin(0.21/0.62/0.82)의 투과율 — 실제 마스크 세기.
    static let base = FilmStockDminRegistry.find("kodak-portra-400")!.dminTransmission

    var rebate: Rebate = .full
    /// 백라이트(필름 밖) 색과 비네팅 세기(0 = 균일).
    var light = SIMD3<Double>(0.95, 0.95, 0.95)
    var vignette = 0.0
    /// 사진 영역 안의 유채색 최박부 띠(밀도, 없으면 nil) — 크롭 안 재검출의 함정.
    var colouredShadow: SIMD3<Double>?
    /// false 면 홀더가 백라이트를 다 가린다(중형 홀더처럼 띠에 광원이 안 보인다).
    var lightVisible = true
    /// 왼쪽 이웃 프레임 자리의 평평한 장면 면(밀도, 없으면 nil) — 띠 안 강등의 함정.
    var neighbourShade: SIMD3<Double>?

    static func density(_ k: Int) -> Double { 0.15 + 1.40 * Double(k) / Double(patchCount - 1) }

    func image() -> CIImage {
        let w = Self.width, h = Self.height
        return SyntheticScan.makeImage(width: w, height: h) { x, y in
            let dx = (Double(x) - Double(w) / 2) / (Double(w) / 2)
            let dy = (Double(y) - Double(h) / 2) / (Double(h) / 2)
            let illumination = light / 0.95 * max(0.35, 1 - vignette * (dx * dx + dy * dy))
            func film(_ d: SIMD3<Double>) -> SIMD3<Double> {
                SIMD3(Self.base.x * pow(10, -d.x), Self.base.y * pow(10, -d.y), Self.base.z * pow(10, -d.z))
                    * illumination
            }
            let holder = SIMD3<Double>(repeating: 0.004) * illumination
            if y < 50 || y >= 950 {
                return lightVisible ? light * max(0.35, 1 - vignette * (dx * dx + dy * dy)) : holder
            }
            let insideImageRows = Self.imageY.contains(y)
            switch rebate {
            case .full:
                if y < 100 || y >= 900 { return holder }
                if !insideImageRows { return film(.zero) }
            case .betweenFramesOnly, .hidden:
                if !insideImageRows { return holder }
            }
            if x < 120, let shade = neighbourShade { return film(shade) }
            if x < 120 || x >= 1380 { return film(SIMD3(1.35, 1.20, 0.95)) }   // 이웃 프레임
            if !Self.imageX.contains(x) { return rebate == .hidden ? holder : film(.zero) }
            if let shadow = colouredShadow, y >= 620, y < 760 { return film(shadow) }
            let k = min(Self.patchCount - 1, (x - Self.imageX.lowerBound) / Self.patchWidth)
            return film(SIMD3(repeating: Self.density(k)))
        }
    }

    /// 사진 영역을 덮는 크롭(정규, CI y-up).
    static var cropTransform: ImageTransform {
        var t = ImageTransform()
        t.cropRect = SIMD4(Double(imageX.lowerBound) / Double(width),
                           Double(height - imageY.upperBound) / Double(height),
                           Double(imageX.count) / Double(width),
                           Double(imageY.count) / Double(height))
        return t
    }

    /// 크롭된 현상 결과(원점 0)에서 웨지 패치 평균.
    static func croppedPatches(_ developed: CIImage) -> [SIMD3<Double>] {
        let e = developed.extent.integral
        let w = Int(e.width), h = Int(e.height)
        var bmp = [Float](repeating: 0, count: w * h * 4)
        ChromabaseEngine.sharedLinearRenderContext.render(
            DisplayGamutMap.apply(to: developed), toBitmap: &bmp, rowBytes: w * 16,
            bounds: e, format: .RGBAf, colorSpace: SyntheticScan.linear)
        return (0..<patchCount).map { k in
            let cx = Int(Double(k * patchWidth + patchWidth / 2) * Double(w) / Double(imageX.count))
            var sum = SIMD3<Double>(repeating: 0), n = 0.0
            for y in (h / 2 - 15)..<(h / 2 + 15) {
                for x in max(0, cx - 8)..<min(w, cx + 8) {
                    let i = (y * w + x) * 4
                    sum += SIMD3(Double(bmp[i]), Double(bmp[i + 1]), Double(bmp[i + 2])); n += 1
                }
            }
            return sum / n
        }
    }
}
