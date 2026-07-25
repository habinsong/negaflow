import XCTest
import CoreImage
import CoreGraphics
import simd
@testable import Chromabase

/// PRINT의 작업공간 계약을 합성 픽스처로 검증한다.
/// 실제 출력 특성은 정확히 매칭되는 printer-class ICC와 실측 holdout이 있어야 평가한다.
final class PrintPaperGradeTests: XCTestCase {

    func testPrintWorkingStagePreservesExtendedValuesExactlyWithoutMeasuredProfile() {
        let width = 257
        let height = 3
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = -0.25 + 1.75 * Float(x) / Float(width - 1)
                let offset = (y * width + x) * 4
                pixels[offset] = value
                pixels[offset + 1] = value * 0.82 + 0.04
                pixels[offset + 2] = value * 1.08 - 0.03
            }
        }
        let input = CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        let output = PrintPaperGrade.apply(to: input)
        let context = CIContext(options: [
            .workingColorSpace: linear,
            .outputColorSpace: linear,
            .workingFormat: CIFormat.RGBAf,
        ])
        var rendered = [Float](repeating: 0, count: pixels.count)
        context.render(
            output,
            toBitmap: &rendered,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: input.extent,
            format: .RGBAf,
            colorSpace: linear
        )

        for index in pixels.indices {
            XCTAssertEqual(rendered[index], pixels[index], accuracy: 1e-6)
        }
        XCTAssertLessThan(rendered[0], 0)
        XCTAssertGreaterThan(rendered[(width - 1) * 4], 1)
    }

    // MARK: main 플랫 마스터 계약 (정보 보존 — RAW/LOG 처럼 보정 여지 유지)

    private let baseRGB = SIMD3<Double>(0.90, 0.57, 0.38)

    /// 밀도 d 의 네거티브 픽셀 = base × 10^−d (채널별). float 픽스처 — 실입력(16bit 스캐너
    /// TIFF/감마 인코딩 JPEG/RAW) 대응. 8bit linear 양자화는 실입력에 없는 dark-floor
    /// 아티팩트(채널별 dmaxNorm 발산 → 가짜 캐스트)를 만들므로 쓰지 않는다.
    private func makeNegative(width: Int, height: Int,
                              density: (Int, Int) -> SIMD3<Double>) -> CIImage {
        var floats = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let d = density(x, y)
                let i = (y * width + x) * 4
                floats[i] = Float(min(1, max(0, baseRGB.x * pow(10, -d.x))))
                floats[i + 1] = Float(min(1, max(0, baseRGB.y * pow(10, -d.y))))
                floats[i + 2] = Float(min(1, max(0, baseRGB.z * pow(10, -d.z))))
                floats[i + 3] = 1
            }
        }
        let data = Data(bytes: floats, count: floats.count * MemoryLayout<Float>.size)
        return CIImage(bitmapData: data, bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                       size: CGSize(width: width, height: height), format: .RGBAf,
                       colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)
    }

    private func renderSRGB(_ img: CIImage, width: Int, height: Int) -> [Float] {
        let ctx = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ])
        var out = [Float](repeating: 0, count: width * height * 4)
        ctx.render(img, toBitmap: &out, rowBytes: width * 4 * MemoryLayout<Float>.size,
                   bounds: CGRect(x: 0, y: 0, width: width, height: height),
                   format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return out
    }

    /// 중립 램프 + 미드톤 유채색 패치 네거티브. 반환: (이미지, 패치 중심 좌표).
    private func makeRampWithColorPatch(width: Int, height: Int) -> (CIImage, (x: Int, y: Int)) {
        let img = makeNegative(width: width, height: height) { x, y in
            let ramp = 0.30 + Double(x) / Double(width - 1) * 2.10
            let inPatch = x >= width * 2 / 5 && x < width * 3 / 5 && y >= height / 3 && y < height * 2 / 3
            if inPatch {
                // positive 에서 R>G>B(주황) 미드톤 패치.
                return SIMD3(1.20 + 0.34, 1.20, 1.20 - 0.34)
            }
            return SIMD3(repeating: ramp)
        }
        return (img, (width / 2, height / 2))
    }

    /// main 은 반전(플랫 마스터) 결과에 룩을 굽지 않는다 — 미드톤 in-gamut 패치에서
    /// 최종 출력 ≈ 반전 직후(디버그 프레임) 출력. 과거의 muted 그레이드/상시 chroma NR/
    /// Vibrance/UnsharpMask 는 이 등식을 깼다(탈색·정보 손실의 원인).
    func testMainTargetBakesNoLookOntoInversionForMidtonePatch() {
        let width = 120, height = 40
        let (neg, patch) = makeRampWithColorPatch(width: width, height: height)
        var params = DevelopParameters()
        params.filmType = .colorNegative
        params.developTarget = .main

        let engine = ChromabaseEngine()
        let base = FilmBase(rgb: baseRGB, source: .border)
        let final = renderSRGB(engine.develop(image: neg, base: base, params: params),
                               width: width, height: height)
        let frames = engine.developDebugFramesScanner(image: neg, base: base, params: params)
        guard let inversion = frames.first(where: { $0.stage == .afterInversion })?.image else {
            return XCTFail("afterInversion 디버그 프레임이 있어야 한다")
        }
        let inverted = renderSRGB(inversion, width: width, height: height)

        let i = (patch.y * width + patch.x) * 4
        for c in 0..<3 {
            XCTAssertEqual(Double(final[i + c]), Double(inverted[i + c]), accuracy: 0.02,
                "main 최종 출력은 미드톤 in-gamut 색에서 반전 결과와 같아야 한다(굽는 룩 없음). " +
                "ch=\(c) final=\(final[i + c]) inversion=\(inverted[i + c])")
        }
    }

    /// 측정 출력 ICC가 없는 작업공간에서 PRINT는 완성된 MAIN과 같아야 한다. 임의의 감마,
    /// 채도, paper black/white 값을 엔진에 굽지 않는다.
    func testPrintTargetWorkingImageEqualsMainAfterUserAdjustments() {
        let width = 120, height = 40
        let (neg, _) = makeRampWithColorPatch(width: width, height: height)
        let base = FilmBase(rgb: baseRGB, source: .border)
        var mainParams = DevelopParameters()
        mainParams.filmType = .colorNegative
        mainParams.developTarget = .main
        mainParams.exposure = 0.37
        mainParams.contrast = 0.21
        mainParams.warmth = -0.14
        mainParams.saturation = 0.18
        mainParams.pointCurves.rgb = [
            CurvePoint(x: 0, y: 0),
            CurvePoint(x: 0.43, y: 0.38),
            CurvePoint(x: 1, y: 1),
        ]
        mainParams.colorMixer.saturation[MixerBand.orange.rawValue] = 0.23
        mainParams.calibration.redSat = 0.17
        var printParams = mainParams
        printParams.developTarget = .print

        let engine = ChromabaseEngine()
        let main = renderSRGB(engine.develop(image: neg, base: base, params: mainParams),
                              width: width, height: height)
        let print_ = renderSRGB(engine.develop(image: neg, base: base, params: printParams),
                                width: width, height: height)

        XCTAssertEqual(main.count, print_.count)
        for index in main.indices {
            XCTAssertEqual(main[index], print_[index], accuracy: 1e-5, "index=\(index)")
        }
    }

    func testPositivePrintWorkingImageEqualsMainAfterUserAdjustments() {
        let width = 96
        let height = 32
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            let v = Double(y) / Double(height - 1)
            for x in 0..<width {
                let u = Double(x) / Double(width - 1)
                let offset = (y * width + x) * 4
                pixels[offset] = Float(-0.08 + 1.28 * u + 0.09 * sin(9 * u + 3 * v))
                pixels[offset + 1] = Float(0.02 + 1.04 * u + 0.07 * cos(7 * u - 4 * v))
                pixels[offset + 2] = Float(-0.03 + 1.19 * u + 0.08 * sin(5 * u + 6 * v))
            }
        }
        let input = CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        var mainParams = DevelopParameters()
        mainParams.filmType = .colorPositive
        mainParams.developTarget = .main
        mainParams.exposure = -0.24
        mainParams.highlight = 0.19
        mainParams.colorDepth = 0.16
        mainParams.colorMixer.hue[MixerBand.blue.rawValue] = -0.12
        mainParams.calibration.blueHue = 0.18
        var printParams = mainParams
        printParams.developTarget = .print

        let engine = ChromabaseEngine()
        let main = renderSRGB(engine.develop(image: input, base: nil, params: mainParams),
                              width: width, height: height)
        let print_ = renderSRGB(engine.develop(image: input, base: nil, params: printParams),
                                width: width, height: height)

        XCTAssertEqual(main.count, print_.count)
        for index in main.indices {
            XCTAssertEqual(main[index], print_[index], accuracy: 1e-5, "index=\(index)")
        }
    }
}
