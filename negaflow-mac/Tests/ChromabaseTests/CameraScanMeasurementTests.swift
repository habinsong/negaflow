import CoreImage
import XCTest
@testable import Chromabase

/// 디지털 카메라 스캔(필름보다 넓게 찍힌 프레임)의 측정 영역·베이스 검출 계약.
/// 2026-10-14 실측 결함: 홀더 가장자리 혼합 화소가 Dmax 를 틀어 R/B 0.72~0.98 캐스트, 크롭 안
/// 재검출이 유채색 그림자를 베이스로 오인(암부 R/B 3.47), 비네팅된 웜 LED 를 베이스로 오인.
final class CameraScanMeasurementTests: XCTestCase {
    private let engine = ChromabaseEngine()

    /// 크롭이면 실제 경로(파라미터의 크롭 → 엔진이 측정 영역 유도)로, 아니면 전체 프레임을 재고
    /// 같은 사진 영역만 잘라 비교한다.
    private func develop(_ frame: CameraScanFrame, crop: Bool, autoLevels: Bool = false)
        -> (patches: [SIMD3<Double>], base: FilmBase?) {
        let image = frame.image()
        let transform = crop ? CameraScanFrame.cropTransform : ImageTransform()
        let base = engine.estimateFilmBase(
            in: image, mode: .auto,
            analysisRegion: AnalysisRegion(transform: transform, imageSize: image.extent.size)
        )
        var params = DevelopParameters()
        params.autoLevels = autoLevels
        params.imageTransform = transform
        var developed = engine.developScanner(image: image, base: base, params: params)
        if !crop {
            developed = ImageTransformStage.apply(to: developed, transform: CameraScanFrame.cropTransform)
        }
        return (CameraScanFrame.croppedPatches(developed), base)
    }

    private func assertNeutral(_ patches: [SIMD3<Double>], tolerance: Double = 0.02,
                               file: StaticString = #filePath, line: UInt = #line) {
        for (k, p) in patches.enumerated() where k >= 2 {
            XCTAssertEqual(p.x / p.z, 1, accuracy: tolerance, "patch \(k)", file: file, line: line)
        }
    }

    /// 홀더가 리베이트를 가려 사진에 붙어 있어도(크롭 없음) Dmax 가 틀어지지 않는다.
    func testHolderEdgeBlendsDoNotSkewDensityRange() {
        var frame = CameraScanFrame()
        frame.rebate = .betweenFramesOnly
        let result = develop(frame, crop: false)
        assertNeutral(result.patches)
        XCTAssertEqual(SyntheticScan.code(SyntheticScan.luma(result.patches[20])), 218, accuracy: 3)
    }

    /// 가장자리 띠 제외는 두께 있는 비필름 영역에만 건다. 베이스 근처 밝기의 넓은 면에서는 게이트
    /// 판정이 양자화 수준 차이로 점점이 뒤집히는데, 그 점마다 이웃을 지우면 필름의 91% 가 사라져
    /// 같은 화상의 원본과 화면용 sRGB 16bit 사본이 Dmax R 0.146 vs 0.238 로 갈렸다(2026-10-14,
    /// 화면·내보내기 불일치의 원인).
    func testEdgeExclusionIgnoresSpeckledGateFlips() throws {
        let width = 2_400, height = 1_600
        var pixels = [UInt16](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let fy = Double(y) / Double(height - 1)
            for x in 0..<width {
                let fx = Double(x) / Double(width - 1)
                let density = 1.0 - (0.05 + 0.9 * (0.5 + 0.5 * sin(fx * 7.1) * cos(fy * 5.3)))
                let i = (y * width + x) * 4
                pixels[i] = UInt16(0.86 * (0.12 + 0.88 * density) * 65_535)
                pixels[i + 1] = UInt16(0.68 * (0.10 + 0.90 * density * 0.94) * 65_535)
                pixels[i + 2] = UInt16(0.50 * (0.08 + 0.92 * density * 0.88) * 65_535)
                pixels[i + 3] = UInt16.max
            }
        }
        let source = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64,
            bytesPerRow: width * 8, space: SyntheticScan.linear,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(bytes: pixels, count: pixels.count * 2) as CFData)!,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let original = CIImage(cgImage: source)
        // 화면 프리뷰 raw 와 같은 사본 — sRGB 16bit 로 굳혀 다시 읽는다.
        let copy = CIImage(cgImage: try XCTUnwrap(ChromabaseEngine.sharedLinearRenderContext.createCGImage(
            original, from: original.extent, format: .RGBA16, colorSpace: SyntheticScan.srgb)))
        // 이 장면은 베이스 추정이 장면 중간에 앉는다(게이트가 넓은 면을 가른다).
        let base = FilmBase(rgb: SIMD3(0.5322265625, 0.497314453125, 0.434814453125), source: .auto)
        let a = try XCTUnwrap(NegativeInversion.sampleStats(original, base: base)).dmaxNorm
        let b = try XCTUnwrap(NegativeInversion.sampleStats(copy, base: base)).dmaxNorm
        for (x, y) in [(a.x, b.x), (a.y, b.y), (a.z, b.z)] {
            XCTAssertLessThan(abs(log(x / y)), 0.1, "같은 화상의 Dmax 가 갈렸다 \(a) vs \(b)")
        }
    }

    /// 흩어진 단일 점(게이트를 넘은 칸)은 이웃을 지우지 않는다 — 점이 몰린 최농부가 함께 사라지면
    /// Dmax 가 낮게 잡힌다. Windows `test_edge_exclusion_ignores_isolated_gate_flips` 와 같은 픽스처.
    func testEdgeExclusionIgnoresIsolatedGateFlips() throws {
        let width = 320, height = 213, maxDensity = 1.6
        let base = CameraScanFrame.base
        let image = SyntheticScan.makeImage(width: width, height: height) { x, y in
            let speck = x > width * 2 / 3 && x % 4 == 0 && y % 4 == 0
            let scale = speck ? 1.3 : pow(10, -maxDensity * Double(x) / Double(width - 1))
            return base * scale
        }
        let stats = try XCTUnwrap(NegativeInversion.sampleStats(image, base: FilmBase(rgb: base, source: .manual)))
        for dmax in [stats.dmaxNorm.x, stats.dmaxNorm.y, stats.dmaxNorm.z] {
            XCTAssertGreaterThan(dmax, 0.85 * maxDensity, "고립 점 때문에 최농부가 지워졌다 \(stats.dmaxNorm)")
        }
    }

    /// 크롭하면 베이스는 크롭 바깥 띠에서 찾는다 — 사진 안의 유채색 그림자를 베이스로 잡지 않는다.
    func testCropFindsBaseOutsideAndIgnoresColouredShadow() throws {
        var frame = CameraScanFrame()
        frame.colouredShadow = SIMD3(0.12, 0.30, 0.22)
        let result = develop(frame, crop: true)
        let base = try XCTUnwrap(result.base).rgb
        let truth = CameraScanFrame.base
        for (estimate, actual) in [(base.x, truth.x), (base.y, truth.y), (base.z, truth.z)] {
            XCTAssertEqual(estimate / actual, 1, accuracy: 0.02)
        }
        assertNeutral(result.patches)
    }

    /// 크롭 바깥 띠에서는 비네팅으로 베이스만큼 어두워진 웜 LED 를 색도로 걸러 낸다.
    func testCropBandRejectsDimWarmBacklight() throws {
        var frame = CameraScanFrame()
        frame.light = SIMD3(0.95, 0.836, 0.684)   // 웜 LED(1 : 0.88 : 0.72)
        frame.vignette = 0.55
        let result = develop(frame, crop: true)
        let base = try XCTUnwrap(result.base).rgb
        let expectedLogRB = log10((CameraScanFrame.base.x * 1.0) / (CameraScanFrame.base.z * 0.72))
        XCTAssertEqual(log10(base.x / base.z), expectedLogRB, accuracy: 0.05, "백라이트 색도를 베이스로 잡았다")
        assertNeutral(result.patches, tolerance: 0.03)
    }

    /// 홀더가 광원을 가려 띠에 광원이 없으면 강등하지 않는다 — 이웃 프레임의 얇은 푸른 그림자 면은
    /// 베이스보다 오렌지지만(로그 R/B +0.37) 빨강이 거의 감쇠되지 않아 "광원 × 마스크" 관계가 아니다.
    func testCropBandKeepsBaseWhenLightIsHidden() throws {
        var frame = CameraScanFrame()
        frame.lightVisible = false
        frame.neighbourShade = SIMD3(0.08, 0.20, 0.45)
        let result = develop(frame, crop: true)
        let base = try XCTUnwrap(result.base).rgb
        let truth = CameraScanFrame.base
        for (estimate, actual) in [(base.x, truth.x), (base.y, truth.y), (base.z, truth.z)] {
            XCTAssertEqual(estimate / actual, 1, accuracy: 0.02, "띠의 장면 면을 베이스로 잡았다 \(base)")
        }
        assertNeutral(result.patches)
    }

    /// 크롭이 베이스를 잘라 내 띠에 짙은 이웃 프레임·홀더만 남으면 띠에서 고르지 않는다 — 크롭 안
    /// 사진에 그보다 뚜렷이 밝은 필름이 있으니 띠 값은 베이스일 수 없다. 크롭이 없을 때와 같은 답을
    /// 낸다(2026-10-14 실측: 크롭 후 자동 베이스 0.034/0.013/0.006, 크롭 전 0.19/0.094/0.071).
    func testCropThatRemovesBaseFallsBackToWholeFrame() throws {
        var frame = CameraScanFrame()
        frame.rebate = .hidden
        frame.lightVisible = false
        let cropped = try XCTUnwrap(develop(frame, crop: true).base).rgb
        let whole = try XCTUnwrap(develop(frame, crop: false).base).rgb
        let truth = CameraScanFrame.base
        for channel in 0..<3 {
            XCTAssertEqual(cropped[channel] / whole[channel], 1, accuracy: 0.02, "크롭이 베이스를 바꿨다 \(cropped) vs \(whole)")
            XCTAssertGreaterThan(cropped[channel] / truth[channel], 0.6, "띠의 짙은 면을 베이스로 잡았다 \(cropped)")
        }
        assertNeutral(develop(frame, crop: true).patches, tolerance: 0.03)
    }

    /// 베이스가 화면에 없는 컷(리베이트 없이 사진만 스캔): 가장 얇은 면이 결이 있어(이웃 15% 문턱에
    /// 조각나) 성분이 되지 못해도, 더 어두운 매끈한 면을 베이스로 잡지 않는다 — 그보다 밝은 필름이
    /// 있으면 필름의 가장 밝은 면까지 올린다. 크롭 안 사진 탐색도 같은 규칙이다.
    func testFrameWithoutVisibleBaseDoesNotSettleOnSmoothMidtone() throws {
        let base = CameraScanFrame.base
        let image = SyntheticScan.makeImage(width: 1024, height: 640) { x, y in
            // 왼쪽 40%: 8px 바둑판(밀도 0.02 / 0.30) — 얇은 면이 대각으로만 이어진다. 나머지: 매끈한 0.40.
            let density = x < 410 ? (((x / 8) + (y / 8)) % 2 == 0 ? 0.02 : 0.30) : 0.40
            return base * pow(10, -density)
        }
        let crop = ImageTransform(cropRect: SIMD4(0.02, 0.02, 0.96, 0.96))
        for region in [nil, AnalysisRegion(transform: crop, imageSize: image.extent.size)] {
            let estimate = try XCTUnwrap(engine.estimateFilmBase(in: image, mode: .auto, analysisRegion: region)).rgb
            for channel in 0..<3 {
                XCTAssertGreaterThan(estimate[channel] / base[channel], 0.75,
                                     "매끈한 중간 밀도 면을 베이스로 잡았다 \(estimate) (crop: \(region != nil))")
                XCTAssertLessThan(estimate[channel] / base[channel], 1.02)
            }
        }
    }

    /// 자동 레벨도 크롭 안에서 잰다 — 홀더·백라이트를 화이트/블랙포인트로 잡지 않는다.
    func testAutoLevelsMeasuresInsideCrop() {
        let result = develop(CameraScanFrame(), crop: true, autoLevels: true)
        assertNeutral(result.patches)
        XCTAssertGreaterThanOrEqual(SyntheticScan.code(SyntheticScan.luma(result.patches[20])), 245)
    }

    /// 측정 영역 = 크롭을 원본 좌표로 되돌린 사각형. 회전·뒤집기만으로는 영역이 생기지 않는다.
    func testAnalysisRegionFollowsCropAndStraighten() throws {
        let size = CGSize(width: 1500, height: 1000)
        let crop = try XCTUnwrap(AnalysisRegion(transform: CameraScanFrame.cropTransform, imageSize: size))
        XCTAssertEqual(crop.unitRect.minX, 140.0 / 1500, accuracy: 1e-9)
        XCTAssertEqual(crop.unitRect.minY, 170.0 / 1000, accuracy: 1e-9)
        XCTAssertEqual(crop.unitRect.width, 1220.0 / 1500, accuracy: 1e-9)

        var rotated = ImageTransform(); rotated.rotation = .deg90; rotated.flipHorizontal = true
        XCTAssertNil(AnalysisRegion(transform: rotated, imageSize: size))

        var tilted = CameraScanFrame.cropTransform; tilted.straightenAngle = 3
        let tiltedRegion = try XCTUnwrap(AnalysisRegion(transform: tilted, imageSize: size))
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(tiltedRegion.unitRect))
        XCTAssertLessThan(tiltedRegion.unitRect.width, crop.unitRect.width + 1e-9)

        XCTAssertNil(AnalysisRegion.cacheKey(for: rotated))
        var aspectOnly = CameraScanFrame.cropTransform; aspectOnly.cropAspect = 1.5
        XCTAssertEqual(AnalysisRegion.cacheKey(for: aspectOnly), AnalysisRegion.cacheKey(for: CameraScanFrame.cropTransform))
    }
}
