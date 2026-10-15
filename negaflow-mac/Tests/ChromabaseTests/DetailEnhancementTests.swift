import CoreImage
import XCTest
@testable import Chromabase

/// 선명도·부분 대비 계약. Windows `detail_enhancement_tests.cpp` 와 같은 픽스처·문턱이다.
final class DetailEnhancementTests: XCTestCase {
    private static func encode(_ v: Double) -> Double {
        v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }
    private static func decode(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    /// 감마 휘도 행 하나(가운데 행).
    private func gammaRow(_ image: CIImage) -> [Double] {
        let e = image.extent.integral
        let w = Int(e.width), h = Int(e.height)
        var bmp = [Float](repeating: 0, count: w * h * 4)
        ChromabaseEngine.sharedLinearRenderContext.render(
            image, toBitmap: &bmp, rowBytes: w * 16, bounds: e, format: .RGBAf, colorSpace: SyntheticScan.linear)
        let y = h / 2
        return (0..<w).map { x in
            let i = (y * w + x) * 4
            return Self.encode(0.2126 * Double(bmp[i]) + 0.7152 * Double(bmp[i + 1]) + 0.0722 * Double(bmp[i + 2]))
        }
    }

    private func grey(_ gamma: Double) -> SIMD3<Double> { SIMD3(repeating: Self.decode(gamma)) }

    /// 같은 사진의 원본과 반 크기 프록시에서 선명도 헤일로가 **사진 대비** 같은 폭이다 — 화면에서 본
    /// 선명도가 내보낸 파일과 같다. 예전 고정 픽셀 반경은 프록시에서 헤일로가 2 배 넓었다.
    func testSharpenHaloScalesWithImageNotPixels() {
        func haloWidthFraction(width: Int) -> Double {
            let image = SyntheticScan.makeImage(width: width, height: 16) { x, _ in
                self.grey(x < width / 2 ? 0.30 : 0.70)
            }
            let row = gammaRow(DetailEnhancement.sharpen(image, sharpness: 1))
            let peak = row[(width / 2)...].max()! - 0.70
            let wide = row[(width / 2)...].filter { $0 - 0.70 > 0.1 * peak }.count
            return Double(wide) / Double(width)
        }
        let full = haloWidthFraction(width: 6_000)
        let proxy = haloWidthFraction(width: 3_000)
        XCTAssertGreaterThan(full, 0)
        XCTAssertEqual(proxy / full, 1, accuracy: 0.35, "프록시 헤일로 \(proxy) vs 원본 \(full)")
    }

    /// 문턱 아래 미세 진폭(스캐너 노이즈·그레인 바닥)은 키우지 않고, 경계만 날카롭게 한다.
    func testSharpenLeavesSubThresholdNoiseAlone() {
        let width = 6_000
        let image = SyntheticScan.makeImage(width: width, height: 16) { x, _ in
            if x >= width / 2 { return self.grey(x < width * 3 / 4 ? 0.35 : 0.65) }
            return self.grey(0.45 + (x % 2 == 0 ? 0.0015 : -0.0015))
        }
        let before = gammaRow(image), after = gammaRow(DetailEnhancement.sharpen(image, sharpness: 1))
        func ripple(_ row: [Double]) -> Double {
            (100..<1_000).map { abs(row[$0] - row[$0 + 1]) }.reduce(0, +) / 900
        }
        XCTAssertLessThan(ripple(after) / ripple(before), 1.25, "노이즈 바닥을 키웠다")
        let overshoot = after[(width * 3 / 4)..<(width * 3 / 4 + 20)].max()! - 0.65
        XCTAssertGreaterThan(overshoot, 0.02, "경계가 날카로워지지 않았다")
    }

    /// 휘도에만 건다 — 유채색 경계에서 화소의 색 비율(색상·채도)이 그대로다.
    func testSharpenAndClarityPreserveChannelRatios() throws {
        let width = 3_000
        let colour = SIMD3<Double>(0.62, 0.30, 0.12)
        let image = SyntheticScan.makeImage(width: width, height: 16) { x, _ in
            colour * (x < width / 2 ? 0.25 : 1.0) * (1 + 0.1 * sin(Double(x) / 9))
        }
        for output in [DetailEnhancement.sharpen(image, sharpness: 1),
                       DetailEnhancement.localContrast(image, clarity: 1),
                       DetailEnhancement.localContrast(image, clarity: -1)] {
            var bmp = [Float](repeating: 0, count: width * 16 * 4)
            ChromabaseEngine.sharedLinearRenderContext.render(
                output, toBitmap: &bmp, rowBytes: width * 16, bounds: image.extent,
                format: .RGBAf, colorSpace: SyntheticScan.linear)
            for x in stride(from: 10, to: width - 10, by: 37) {
                let i = (8 * width + x) * 4
                XCTAssertEqual(Double(bmp[i]) / Double(bmp[i + 1]), colour.x / colour.y, accuracy: 2e-3)
                XCTAssertEqual(Double(bmp[i + 1]) / Double(bmp[i + 2]), colour.y / colour.z, accuracy: 4e-3)
            }
        }
    }

    /// 부분 대비 − 는 미드톤 질감을 줄이되 큰 경계는 번지지 않는다(예전: 흐린 사본과 섞어 경계가
    /// 반경만큼 번졌다).
    func testNegativeClarityFlattensTextureButKeepsEdges() {
        let width = 3_000
        let image = SyntheticScan.makeImage(width: width, height: 16) { x, _ in
            x < width / 2
                ? self.grey(0.45 + 0.04 * sin(Double(x) * 2 * .pi / 40))
                : self.grey(0.85)
        }
        let before = gammaRow(image), after = gammaRow(DetailEnhancement.localContrast(image, clarity: -1))
        func amplitude(_ row: [Double]) -> Double {
            let span = row[400..<1_200]
            return (span.max()! - span.min()!) / 2
        }
        XCTAssertLessThan(amplitude(after), 0.6 * amplitude(before), "질감이 줄지 않았다")
        // 큰 경계(0.49 → 0.85)는 여전히 한 화소 안에서 끊긴다 — 흐린 사본과 섞으면 이 점프가 준다.
        func jump(_ row: [Double]) -> Double {
            ((width / 2 - 3)..<(width / 2 + 3)).map { abs(row[$0 + 1] - row[$0]) }.max()!
        }
        XCTAssertGreaterThan(jump(after), 0.9 * jump(before), "큰 경계가 번졌다")
    }

    /// 부분 대비 + 는 미드톤 질감을 키우고 깊은 암부는 훨씬 덜 건드린다.
    func testPositiveClarityFavoursMidtones() {
        let width = 3_000
        func boost(around level: Double) -> Double {
            let image = SyntheticScan.makeImage(width: width, height: 16) { x, _ in
                self.grey(level + 0.02 * sin(Double(x) * 2 * .pi / 40))
            }
            let before = gammaRow(image), after = gammaRow(DetailEnhancement.localContrast(image, clarity: 1))
            let b = before[800..<2_200], a = after[800..<2_200]
            return (a.max()! - a.min()!) / (b.max()! - b.min()!)
        }
        let mid = boost(around: 0.50), shadow = boost(around: 0.06)
        XCTAssertGreaterThan(mid, 1.4, "미드톤 질감이 커지지 않았다")
        XCTAssertLessThan(shadow - 1, (mid - 1) / 2, "암부를 미드톤만큼 건드렸다")
    }

    /// SP 타겟은 질감 단계에서 사용자 슬라이더와 별개로 약한 부분 대비를 기본으로 얹는다(쫀득한 미드).
    /// 다른 타겟은 슬라이더가 0 이면 질감 단계가 항등이다.
    func testSPTargetAddsBaselineLocalContrastInTextureStage() {
        let width = 3_000
        let image = SyntheticScan.makeImage(width: width, height: 16) { x, _ in
            self.grey(0.50 + 0.02 * sin(Double(x) * 2 * .pi / 40))
        }
        func amplitude(_ target: DevelopTarget) -> Double {
            var params = DevelopParameters()
            params.developTarget = target
            let row = gammaRow(TextureStage.apply(to: image, params: params))[800..<2_200]
            return (row.max()! - row.min()!) / 2
        }
        let main = amplitude(.main), sp = amplitude(.sp3000)
        XCTAssertEqual(main, 0.02, accuracy: 0.001, "MAIN 질감 단계는 항등이어야 한다")
        XCTAssertGreaterThan(sp, main * 1.08, "SP 기본 부분 대비가 걸리지 않았다")
        XCTAssertLessThan(sp, main * 1.35, "SP 기본 부분 대비는 약해야 한다")
    }
}
