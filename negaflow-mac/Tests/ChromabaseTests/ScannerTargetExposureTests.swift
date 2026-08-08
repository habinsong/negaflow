import XCTest
import CoreImage
@testable import Chromabase

/// NORITSU/FUJI 타겟의 합성 노출 진단.
///
/// 실제 동일 네거티브의 paired scanner 출력 없이 합성 이미지의 평균/중앙값으로 장비 노출과
/// 미감을 판정할 수 없으므로 XCTest 품질 게이트가 아니다. 필요할 때 수동 진단에만 사용한다.
final class ScannerTargetExposureTests: XCTestCase {

    private func clampByte(_ v: Double) -> UInt8 {
        UInt8(min(255, max(0, Int(v * 255.0 + 0.5))))
    }

    private func makeLinearImage(width: Int, height: Int,
                                 pixel: (Int, Int) -> (Double, Double, Double)) -> CIImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let (r, g, b) = pixel(x, y)
                bytes[i] = clampByte(r); bytes[i + 1] = clampByte(g); bytes[i + 2] = clampByte(b)
                bytes[i + 3] = 255
            }
        }
        var mutable = bytes
        let cg = CGContext(data: &mutable, width: width, height: height,
                           bitsPerComponent: 8, bytesPerRow: width * 4,
                           space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        return CIImage(cgImage: cg)
    }

    private func renderSRGB8(_ image: CIImage, width: Int, height: Int) -> [UInt8] {
        let ctx = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ])
        var out = [UInt8](repeating: 0, count: width * height * 4)
        ctx.render(image, toBitmap: &out, rowBytes: width * 4,
                   bounds: CGRect(x: 0, y: 0, width: width, height: height),
                   format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return out
    }

    private func meanLinearLuma(_ px: [UInt8]) -> Double {
        var sum = 0.0
        var n = 0
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = ScannerTargetGrade.srgbDecode(Double(px[i]) / 255.0)
            let g = ScannerTargetGrade.srgbDecode(Double(px[i + 1]) / 255.0)
            let b = ScannerTargetGrade.srgbDecode(Double(px[i + 2]) / 255.0)
            sum += 0.2126 * r + 0.7152 * g + 0.0722 * b
            n += 1
        }
        return sum / Double(n)
    }

    private func medianLinearLuma(_ px: [UInt8]) -> Double {
        var lumas: [Double] = []
        lumas.reserveCapacity(px.count / 4)
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = ScannerTargetGrade.srgbDecode(Double(px[i]) / 255.0)
            let g = ScannerTargetGrade.srgbDecode(Double(px[i + 1]) / 255.0)
            let b = ScannerTargetGrade.srgbDecode(Double(px[i + 2]) / 255.0)
            lumas.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
        }
        lumas.sort()
        return lumas.isEmpty ? 0 : lumas[lumas.count / 2]
    }

    private func developed(
        target: DevelopTarget,
        input: CIImage,
        base: FilmBase?,
        width: Int,
        height: Int
    ) -> [UInt8] {
        var params = DevelopParameters()
        params.filmType = .colorNegative
        params.developTarget = target
        return renderSRGB8(
            ChromabaseEngine().develop(image: input, base: base, params: params),
            width: width, height: height)
    }

    /// 가장자리 = 베이스. 내부 = 지정한 밀도 분포.
    private func makeNegative(width: Int, height: Int, base: SIMD3<Double>,
                              density: (Double) -> Double) -> CIImage {
        let bx = Int(Double(width) * 0.08), by = Int(Double(height) * 0.08)
        return makeLinearImage(width: width, height: height) { x, y in
            let isBorder = x < bx || x >= width - bx || y < by || y >= height - by
            let f = Double(x) / Double(width - 1)
            let d = isBorder ? 0.0 : density(f)
            let atten = pow(10.0, -d)
            return (base.x * atten, base.y * atten, base.z * atten)
        }
    }

    /// 세 가지 서로 다른 합성 밀도 분포(균일 램프/미드 중심/저조도)에서 두 스캐너 타겟의
    /// 평균 linear 노출이 MAIN 근처에 있어야 한다(한 분포에 과적합 금지 — 검증된 교훈).
    func diagnoseEmulationTargetExposureOnSyntheticFixtures() {
        let width = 192, height = 96
        let base = SIMD3<Double>(0.82, 0.55, 0.34)
        let fixtures: [(String, (Double) -> Double)] = [
            ("uniform-ramp", { f in 0.35 + 1.5 * f }),
            ("mid-heavy", { f in
                let t = 2.0 * f - 1.0
                return 1.05 + 0.55 * t * t * t + 0.25 * t
            }),
            ("low-key", { f in 1.25 + 0.55 * (2.0 * f - 1.0) }),
        ]
        for (name, density) in fixtures {
            let input = makeNegative(width: width, height: height, base: base, density: density)
            let fb = FilmBase(rgb: base, source: .border)
            let main = developed(target: .main, input: input, base: fb, width: width, height: height)
            let nor = developed(target: .noritsu, input: input, base: fb, width: width, height: height)
            let sp = developed(target: .sp3000, input: input, base: fb, width: width, height: height)

            let mMain = meanLinearLuma(main)
            let norStops = log2(meanLinearLuma(nor) / mMain)
            let spStops = log2(meanLinearLuma(sp) / mMain)
            XCTAssertGreaterThan(norStops, -0.30,
                "\(name): NORITSU 가 MAIN 대비 과도하게 어둡다(\(norStops) 스탑)")
            XCTAssertLessThan(norStops, 0.15,
                "\(name): NORITSU 가 MAIN 대비 과도하게 밝다(\(norStops) 스탑)")
            XCTAssertGreaterThan(spStops, -0.25,
                "\(name): FUJI 가 MAIN 대비 과도하게 어둡다(\(spStops) 스탑)")
            XCTAssertLessThan(spStops, 0.20,
                "\(name): FUJI 가 MAIN 대비 과도하게 밝다(\(spStops) 스탑)")
            // roll-label matched 출력 통계의 상대 방향: SP-3000(FUJI)의 미드톤이 NORITSU보다
            // 밝다. 이 테스트는 고정된 상대 톤 회귀만 확인하며, 공개되지 않은 로컬 처리나
            // 실제 장치 정확도를 추론하지 않는다.
            let norMid = log2(medianLinearLuma(nor) / max(medianLinearLuma(main), 1e-6))
            let spMid = log2(medianLinearLuma(sp) / max(medianLinearLuma(main), 1e-6))
            XCTAssertGreaterThan(spMid, norMid,
                "\(name): 실측 방향(SP 미드 > NOR 미드)이 유지되어야 한다")
        }
    }
}
