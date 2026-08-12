import XCTest
import CoreImage
@testable import Chromabase

/// 네거티브 변환 품질 개선(2026-07-04) 검증 — 전부 합성 픽스처 + 수치 측정.
///   • Manual base = 절대 Dmin 의미론
///   • FilmBaseEstimator: 클러스터 중앙값(채널 상관 보존) + B&W 중립 베이스
///   • 자동 보정(AutoLevels/NeutralBalance) opt-in 게이팅
///   • Film stock / Light source 프로파일 분리(실측 우선)
///   • FilmBasePicker 영역 샘플링
final class NegativeBaseWorkflowTests: XCTestCase {

    // MARK: 헬퍼

    /// 기존 ChromabaseTests 의 makeTestImage 와 동일한 관례(CGContext 경유):
    /// bytes 의 첫 행 = 이미지의 맨 위(표시 기준). CI 좌표(y-up)에서는 최대 y.
    private func makeLinearImage(bytes: [UInt8], width: Int, height: Int) -> CIImage {
        var mutable = bytes
        let cg = CGContext(data: &mutable, width: width, height: height,
                           bitsPerComponent: 8, bytesPerRow: width * 4,
                           space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        return CIImage(cgImage: cg)
    }

    private func renderLinearRGBA8(_ image: CIImage, width: Int, height: Int) -> [UInt8] {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        var out = [UInt8](repeating: 0, count: width * height * 4)
        ctx.render(image, toBitmap: &out, rowBytes: width * 4,
                   bounds: CGRect(x: 0, y: 0, width: width, height: height),
                   format: .RGBA8, colorSpace: linear)
        return out
    }

    private func clampByte(_ v: Double) -> UInt8 {
        UInt8(min(255, max(0, Int(v * 255.0 + 0.5))))
    }

    /// 가장자리 = 미노광 베이스, 내부 = 장면 밀도로 구성한 합성 네거티브.
    private func makeSyntheticNegative(
        width: Int, height: Int,
        base: SIMD3<Double>,
        borderFraction: Double = 0.08,
        sceneDensity: (Int, Int) -> Double,
        mutate: ((inout [UInt8], Int, Int) -> Void)? = nil
    ) -> CIImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let bx = Int(Double(width) * borderFraction)
        let by = Int(Double(height) * borderFraction)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let isBorder = x < bx || x >= width - bx || y < by || y >= height - by
                let density = isBorder ? 0.0 : sceneDensity(x, y)
                let atten = pow(10.0, -density)
                bytes[i]     = clampByte(base.x * atten)
                bytes[i + 1] = clampByte(base.y * atten)
                bytes[i + 2] = clampByte(base.z * atten)
                bytes[i + 3] = 255
            }
        }
        mutate?(&bytes, width, height)
        return makeLinearImage(bytes: bytes, width: width, height: height)
    }

    // MARK: Manual base = 절대 Dmin

    /// Manual base 절대값이 결과에 반영돼야 한다(과거 "비율만 반영"은 절대값 변화가 무시됨).
    /// 같은 비율·다른 밝기의 base 두 개는 달라야 하고, 더 어두운(낮은 투과율) Dmin 은
    /// 장면을 상대적으로 저밀도(=반전 후 더 어두운 positive) 쪽으로 매핑해야 한다.
    func testManualBaseAbsoluteValueChangesInversion() {
        let width = 64, height = 32
        let trueBase = SIMD3<Double>(0.80, 0.52, 0.34)
        let input = makeSyntheticNegative(width: width, height: height, base: trueBase) { x, _ in
            0.35 + 1.3 * Double(x) / Double(width - 1)
        }
        let brightBase = FilmBase(rgb: trueBase, source: .manual)
        // 같은 R:G:B 비율, 절대 밝기만 60%로 낮춘 base — 과거 의미론에서는 결과가 동일했다.
        let darkBase = FilmBase(rgb: trueBase * 0.6, source: .manual)

        let outBright = renderLinearRGBA8(
            NegativeInversion.apply(to: input, base: brightBase), width: width, height: height)
        let outDark = renderLinearRGBA8(
            NegativeInversion.apply(to: input, base: darkBase), width: width, height: height)

        func meanLuma(_ px: [UInt8]) -> Double {
            var sum = 0.0
            for i in stride(from: 0, to: px.count, by: 4) {
                sum += (Double(px[i]) + Double(px[i + 1]) + Double(px[i + 2])) / 3.0
            }
            return sum / Double(px.count / 4)
        }
        let lumaBright = meanLuma(outBright)
        let lumaDark = meanLuma(outDark)
        // Dmin 이 어두워지면 모든 장면 밀도(log10(dmin/t))가 낮아져 positive 는 어두워진다.
        XCTAssertLessThan(lumaDark, lumaBright - 5,
            "Manual base 절대값이 반영돼야 한다(비율만 반영되던 과거 동작 회귀 방지). " +
            "bright=\(lumaBright) dark=\(lumaDark)")
    }

    /// 중립 회색 장면 + 정확한 manual base → 반전 후에도 중립(채널 간 균형 유지).
    /// float 픽스처를 쓴다 — 8bit 픽스처는 딥섀도(밀도 1.4+)에서 채널별 양자화(B 채널
    /// byte 1~3)가 가짜 채널 캐스트를 만들어 알고리즘 중립성이 아니라 픽스처 한계를
    /// 측정하게 된다(실입력 16bit 스캐너 TIFF 에는 없는 아티팩트).
    func testManualBaseExactDminKeepsNeutralSceneNeutral() {
        let width = 96, height = 32
        let trueBase = SIMD3<Double>(0.78, 0.50, 0.33)
        let bx = Int(Double(width) * 0.08), by = Int(Double(height) * 0.08)
        var floats = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let isBorder = x < bx || x >= width - bx || y < by || y >= height - by
                // 중립 밀도 램프(세 채널 동일 밀도)
                let density = isBorder ? 0.0 : 0.4 + 1.4 * Double(x) / Double(width - 1)
                let atten = pow(10.0, -density)
                floats[i] = Float(trueBase.x * atten)
                floats[i + 1] = Float(trueBase.y * atten)
                floats[i + 2] = Float(trueBase.z * atten)
                floats[i + 3] = 1
            }
        }
        let input = CIImage(
            bitmapData: Data(bytes: floats, count: floats.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
        let output = renderLinearRGBA8(
            NegativeInversion.apply(to: input, base: FilmBase(rgb: trueBase, source: .manual)),
            width: width, height: height)
        // 중간톤 픽셀들의 채널 불균형 측정.
        let midY = height / 2
        var maxImbalance = 0
        for x in (width / 4)..<(width * 3 / 4) {
            let i = (midY * width + x) * 4
            let r = Int(output[i]), g = Int(output[i + 1]), b = Int(output[i + 2])
            maxImbalance = max(maxImbalance, abs(r - g), abs(g - b), abs(r - b))
        }
        XCTAssertLessThan(maxImbalance, 14,
            "정확한 Dmin 이면 중립 장면은 반전 후에도 중립이어야 한다. maxImbalance=\(maxImbalance)")
    }

    // MARK: FilmBaseEstimator — 클러스터 중앙값 + B&W

    /// 채널 독립 이상치(한 채널만 부풀린 픽셀)가 섞여도 베이스 비율이 왜곡되면 안 된다.
    /// 과거 채널별 독립 p95 는 각 채널의 백분위가 다른 픽셀에서 와서 비율이 깨졌다.
    func testEstimatorRecoversBaseDespiteChannelIndependentOutliers() {
        let width = 160, height = 120
        let trueBase = SIMD3<Double>(0.82, 0.55, 0.34)
        let image = makeSyntheticNegative(width: width, height: height, base: trueBase,
                                          sceneDensity: { _, _ in 0.9 }) { bytes, w, h in
            // 가장자리 베이스 픽셀 중 5%의 R 채널만 +0.10 (여전히 R≥G≥B, luma 범위 통과).
            var count = 0
            for y in 0..<h where y % 20 == 0 {
                for x in 0..<w where x < Int(Double(w) * 0.08) {
                    let i = (y * w + x) * 4
                    bytes[i] = UInt8(min(255, Int(bytes[i]) + 26))
                    count += 1
                }
            }
            XCTAssertGreaterThan(count, 0)
        }
        guard let estimated = FilmBaseEstimator.estimate(from: image) else {
            return XCTFail("합성 가장자리 베이스에서 추정이 성공해야 한다")
        }
        XCTAssertEqual(estimated.rgb.x, trueBase.x, accuracy: 0.04, "R 채널 왜곡")
        XCTAssertEqual(estimated.rgb.y, trueBase.y, accuracy: 0.04, "G 채널 왜곡")
        XCTAssertEqual(estimated.rgb.z, trueBase.z, accuracy: 0.04, "B 채널 왜곡")
        // 비율(오렌지 마스크 제거의 핵심)이 보존되는지: R/B 비율 오차 10% 이내.
        let trueRatio = trueBase.x / trueBase.z
        let estRatio = estimated.rgb.x / max(estimated.rgb.z, 1e-6)
        XCTAssertEqual(estRatio, trueRatio, accuracy: trueRatio * 0.10,
            "채널 독립 이상치가 base 비율을 왜곡하면 안 된다")
    }

    /// B&W(중립 회색) 베이스: 과거 R−B≥0.06 조건이 회색을 전부 탈락시켰다.
    func testEstimatorFindsNeutralBaseForBWNegative() {
        let width = 160, height = 120
        let trueBase = SIMD3<Double>(0.75, 0.75, 0.75)
        let image = makeSyntheticNegative(width: width, height: height, base: trueBase,
                                          sceneDensity: { _, _ in 1.1 })
        guard let estimated = FilmBaseEstimator.estimate(from: image, neutralBase: true) else {
            return XCTFail("중립 베이스 추정이 성공해야 한다 (B&W)")
        }
        XCTAssertEqual(estimated.rgb.x, 0.75, accuracy: 0.05)
        XCTAssertEqual(estimated.rgb.y, 0.75, accuracy: 0.05)
        XCTAssertEqual(estimated.rgb.z, 0.75, accuracy: 0.05)
        let maxDiff = max(abs(estimated.rgb.x - estimated.rgb.y), abs(estimated.rgb.y - estimated.rgb.z))
        XCTAssertLessThan(maxDiff, 0.05, "중립 베이스는 채널 차가 작아야 한다")
    }

    // MARK: 자동 보정 opt-in

    func testAutoCorrectionsDefaultOffAndDecodeOldJSON() throws {
        let fresh = DevelopParameters()
        XCTAssertFalse(fresh.autoLevels, "AutoLevels 는 opt-in — 기본 꺼짐")
        XCTAssertFalse(fresh.autoNeutralBalance, "NeutralBalance 는 opt-in — 기본 꺼짐")
        XCTAssertNil(fresh.lightSourceProfileID)
        XCTAssertEqual(fresh.developTarget, .main, "main 타겟이 기본이어야 한다")

        // 옛 sidecar JSON(새 키 없음) → 기본값으로 디코드.
        let old = "{\"filmType\":\"colorNegative\"}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DevelopParameters.self, from: old)
        XCTAssertFalse(decoded.autoLevels)
        XCTAssertFalse(decoded.autoNeutralBalance)
        XCTAssertNil(decoded.lightSourceProfileID)

        // 새 값 roundtrip.
        var params = DevelopParameters()
        params.autoLevels = true
        params.autoNeutralBalance = true
        params.lightSourceProfileID = "halogen"
        let round = try JSONDecoder().decode(
            DevelopParameters.self, from: JSONEncoder().encode(params))
        XCTAssertTrue(round.autoLevels)
        XCTAssertTrue(round.autoNeutralBalance)
        XCTAssertEqual(round.lightSourceProfileID, "halogen")
    }

    func testPresetInitCopiesBaseAndAutoCorrectionFields() throws {
        var overrides = DevelopParameters()
        overrides.baseEstimationMode = .preset
        overrides.filmStockDminID = "kodak-portra-400"
        overrides.lightSourceProfileID = "white-led"
        overrides.autoLevels = true
        overrides.autoNeutralBalance = true
        guard let preset = PresetRegistry.loadAll().first else {
            throw XCTSkip("프리셋 리소스 없음")
        }
        let merged = DevelopParameters(preset: preset, overrides: overrides)
        XCTAssertEqual(merged.filmStockDminID, "kodak-portra-400",
            "preset 병합이 filmStockDminID 를 잃으면 안 된다")
        XCTAssertEqual(merged.lightSourceProfileID, "white-led")
        XCTAssertTrue(merged.autoLevels)
        XCTAssertTrue(merged.autoNeutralBalance)
    }

    /// 게이팅 검증: 같은 입력에서 autoLevels/autoNeutralBalance on/off 는 측정 가능하게 다르고,
    /// off 경로는 결정적(재실행 동일)이어야 한다.
    func testNegativePipelineAutoCorrectionsAreOptIn() {
        let width = 96, height = 48
        let trueBase = SIMD3<Double>(0.80, 0.52, 0.34)
        // 채널별로 분포가 어긋난 장면(자동 보정이 실제로 개입할 여지가 있는) 픽스처.
        let input = makeSyntheticNegative(width: width, height: height, base: trueBase) { x, y in
            0.3 + 1.2 * Double(x) / Double(width - 1) + (y % 3 == 0 ? 0.15 : 0.0)
        }
        var off = DevelopParameters()
        off.filmType = .colorNegative
        off.developTarget = .main
        var on = off
        on.autoLevels = true
        on.autoNeutralBalance = true

        let base = FilmBase(rgb: trueBase, source: .border)
        let engine = ChromabaseEngine()
        let outOff1 = renderLinearRGBA8(
            engine.develop(image: input, base: base, params: off), width: width, height: height)
        let outOff2 = renderLinearRGBA8(
            engine.develop(image: input, base: base, params: off), width: width, height: height)
        let outOn = renderLinearRGBA8(
            engine.develop(image: input, base: base, params: on), width: width, height: height)

        XCTAssertEqual(outOff1, outOff2, "자동 보정 off 파이프라인은 결정적이어야 한다")

        var diff = 0.0
        for i in stride(from: 0, to: outOff1.count, by: 4) {
            diff += abs(Double(outOff1[i]) - Double(outOn[i]))
                + abs(Double(outOff1[i + 1]) - Double(outOn[i + 1]))
                + abs(Double(outOff1[i + 2]) - Double(outOn[i + 2]))
        }
        let meanDiff = diff / Double(outOff1.count / 4)
        XCTAssertGreaterThan(meanDiff, 1.0,
            "autoLevels/autoNeutralBalance 를 켜면 결과가 실제로 달라져야 한다(게이팅 증명). meanDiff=\(meanDiff)")
    }

    // MARK: Film stock / Light source 프로파일 분리

    func testLightSourceProfileEffectiveDminAndClamp() {
        guard let portra = FilmStockDminRegistry.find("kodak-portra-400"),
              let halogen = LightSourceProfileRegistry.find("halogen") else {
            return XCTFail("레지스트리 항목 누락")
        }
        let t = portra.dminTransmission
        let effective = halogen.effectiveDminTransmission(for: portra)
        XCTAssertEqual(effective.x, min(t.x * halogen.gain.x, 1.0), accuracy: 1e-9)
        XCTAssertEqual(effective.y, min(t.y * halogen.gain.y, 1.0), accuracy: 1e-9)
        XCTAssertEqual(effective.z, min(t.z * halogen.gain.z, 1.0), accuracy: 1e-9)
        // 극단 게인도 (0,1] 클램프.
        let extreme = LightSourceProfile(id: "x", displayName: "x", gain: SIMD3(99, 99, 99))
        let clamped = extreme.effectiveDminTransmission(for: portra)
        XCTAssertLessThanOrEqual(clamped.x, 1.0)
        XCTAssertLessThanOrEqual(clamped.y, 1.0)
        XCTAssertLessThanOrEqual(clamped.z, 1.0)
    }

    func testLightSourceCalibratedGainFromMeasuredBase() {
        guard let portra = FilmStockDminRegistry.find("kodak-portra-400") else {
            return XCTFail("kodak-portra-400 누락")
        }
        let t = portra.dminTransmission
        // 실측 베이스가 프리셋 대비 R +10% / B −20% 인 광원이라면 게인이 그 비율이어야 한다.
        let measured = SIMD3(t.x * 1.10, t.y * 1.00, t.z * 0.80)
        let gain = LightSourceProfileRegistry.calibratedGain(measuredBase: measured, stock: portra)
        XCTAssertEqual(gain.x, 1.10, accuracy: 1e-6)
        XCTAssertEqual(gain.y, 1.00, accuracy: 1e-6)
        XCTAssertEqual(gain.z, 0.80, accuracy: 1e-6)
        // 비정상 실측은 0.25...4 로 클램프.
        let wild = LightSourceProfileRegistry.calibratedGain(
            measuredBase: SIMD3(t.x * 100, t.y, t.z / 100), stock: portra)
        XCTAssertEqual(wild.x, 4.0, accuracy: 1e-9)
        XCTAssertEqual(wild.z, 0.25, accuracy: 1e-9)
    }

    /// preset 모드 실측 우선: 베이스가 프레임에 보이면 실측(.border/.auto)이 앵커이고,
    /// 안 보이면 프리셋 Dmin × 광원 트림 폴백(.manual)이어야 한다.
    func testPresetModePrefersMeasuredBaseOverDatasheet() {
        let engine = ChromabaseEngine()
        let trueBase = SIMD3<Double>(0.82, 0.55, 0.34)
        let withBorder = makeSyntheticNegative(width: 160, height: 120, base: trueBase,
                                               sceneDensity: { _, _ in 0.9 })
        guard let measured = engine.estimateFilmBase(
            in: withBorder, mode: .preset, filmStockDminID: "kodak-portra-400") else {
            return XCTFail("실측 가능한 이미지에서 추정이 성공해야 한다")
        }
        XCTAssertNotEqual(measured.source, .manual, "실측이 프리셋 폴백보다 우선해야 한다")
        XCTAssertEqual(measured.rgb.x, trueBase.x, accuracy: 0.05)
        XCTAssertEqual(measured.rgb.z, trueBase.z, accuracy: 0.05)

        // 베이스가 전혀 없는 이미지(중간 회색 단색 — 베이스 후보 없음) → 프리셋 폴백 + 광원 트림.
        let flat = [UInt8](repeating: 110, count: 64 * 48 * 4)
        var flatBytes = flat
        for i in stride(from: 3, to: flatBytes.count, by: 4) { flatBytes[i] = 255 }
        let noBase = makeLinearImage(bytes: flatBytes, width: 64, height: 48)
        guard let portra = FilmStockDminRegistry.find("kodak-portra-400"),
              let halogen = LightSourceProfileRegistry.find("halogen") else {
            return XCTFail("레지스트리 항목 누락")
        }
        guard let fallback = engine.estimateFilmBase(
            in: noBase, mode: .preset,
            filmStockDminID: "kodak-portra-400", lightSourceProfileID: "halogen") else {
            return XCTFail("프리셋 폴백이 있어야 한다")
        }
        XCTAssertEqual(fallback.source, .manual)
        let expected = halogen.effectiveDminTransmission(for: portra)
        XCTAssertEqual(fallback.rgb.x, expected.x, accuracy: 1e-6)
        XCTAssertEqual(fallback.rgb.y, expected.y, accuracy: 1e-6)
        XCTAssertEqual(fallback.rgb.z, expected.z, accuracy: 1e-6)
    }

    func testFilmStockProvenanceIsRecorded() {
        guard let portra = FilmStockDminRegistry.find("kodak-portra-400"),
              let cinestill = FilmStockDminRegistry.find("cinestill-800t"),
              let lomo = FilmStockDminRegistry.find("lomo-cn-400") else {
            return XCTFail("레지스트리 항목 누락")
        }
        XCTAssertEqual(portra.provenance, .datasheetCurve,
            "공개 특성곡선이 있는 필름은 datasheetCurve 로 표기")
        XCTAssertEqual(cinestill.provenance, .estimated,
            "공개 데이터 없는 필름은 estimated 로 정직하게 표기")
        XCTAssertEqual(lomo.provenance, .estimated)
    }

    // MARK: FilmBasePicker

    /// 알려진 균일 영역을 y-down 정규좌표로 샘플하면 그 영역 평균이 나와야 한다.
    ///
    /// 아래 절반은 예전에 "어두운 장면"이었지만, 픽커가 장면/비필름 픽셀을 베이스로 받지
    /// 않도록 바뀌면서(testFilmBasePickerRejectsNonBasePicks) 좌표 매핑 검증에는 쓸 수 없다.
    /// 검증 의도(같은 이미지의 다른 영역이 각각 다른 값으로 나온다)는 밝기가 다른 두 베이스로 유지한다.
    func testFilmBasePickerSamplesRegionAtYDownUnitPoint() {
        let width = 120, height = 80
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        // 상단 절반(표시 y-down 기준 y<0.5) = 밝은 오렌지 베이스, 하단 절반 = 살짝 어두운 베이스.
        let top = SIMD3<Double>(0.80, 0.52, 0.34)
        let bottom = SIMD3<Double>(0.62, 0.40, 0.26)
        for y in 0..<height {
            let c = y < height / 2 ? top : bottom
            for x in 0..<width {
                let i = (y * width + x) * 4
                bytes[i] = clampByte(c.x); bytes[i + 1] = clampByte(c.y)
                bytes[i + 2] = clampByte(c.z); bytes[i + 3] = 255
            }
        }
        // CIImage(bitmapData:)는 첫 행이 위(y-down 데이터) — 렌더 시 y-up 으로 뒤집힌다.
        // FilmBasePicker 는 y-down unit 을 받으므로 (0.5, 0.25) = 상단 오렌지 영역이어야 한다.
        let image = makeLinearImage(bytes: bytes, width: width, height: height)
        guard let sampled = FilmBasePicker.sample(in: image, atUnit: CGPoint(x: 0.5, y: 0.25)) else {
            return XCTFail("샘플 실패")
        }
        XCTAssertEqual(sampled.x, top.x, accuracy: 0.03)
        XCTAssertEqual(sampled.y, top.y, accuracy: 0.03)
        XCTAssertEqual(sampled.z, top.z, accuracy: 0.03)

        guard let sampledBottom = FilmBasePicker.sample(in: image, atUnit: CGPoint(x: 0.5, y: 0.75)) else {
            return XCTFail("샘플 실패")
        }
        XCTAssertEqual(sampledBottom.x, bottom.x, accuracy: 0.03)
        XCTAssertEqual(sampledBottom.z, bottom.z, accuracy: 0.03)
    }

    /// 평판 **프리뷰**는 필름 밖까지 담는다 — 투과 광원 창 바깥의 미조사 검정 띠, 빈 베드,
    /// 그리고 프레임 안 장면. 이 픽셀들이 Dmin 으로 앉으면 반전이 전 구간 클리핑돼 현상
    /// 결과가 통째로 검게 죽는다(실측: 검정 띠 클릭 → base 0.004 → 화면 블랙).
    /// 픽커는 그런 값을 받지 않고 실패를 돌려 이전 베이스를 지켜야 한다.
    func testFilmBasePickerRejectsNonBasePicks() {
        let width = 900, height = 1200
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let bed = SIMD3<Double>(0.95, 0.95, 0.95)          // 빈 베드(무필름 백라이트)
        let unlit = SIMD3<Double>(0.004, 0.003, 0.003)     // 광원 창 바깥
        let base = SIMD3<Double>(0.80, 0.52, 0.34)
        let stripX = Int(Double(width) * 0.33)..<Int(Double(width) * 0.69)
        let frameX = Int(Double(width) * 0.355)..<Int(Double(width) * 0.665)
        let litY = Int(Double(height) * 0.15)..<Int(Double(height) * 0.85)
        let frameY = [Int(Double(height) * 0.22)..<Int(Double(height) * 0.47),
                      Int(Double(height) * 0.53)..<Int(Double(height) * 0.78)]
        for y in 0..<height {
            for x in 0..<width {
                var c = litY.contains(y) ? bed : unlit
                if stripX.contains(x), litY.contains(y) {
                    c = base
                    if frameX.contains(x), frameY.contains(where: { $0.contains(y) }) {
                        c = base * pow(10.0, -(0.2 + 1.0 * Double((x + y) % 97) / 96.0))
                    }
                }
                let i = (y * width + x) * 4
                bytes[i] = clampByte(c.x); bytes[i + 1] = clampByte(c.y)
                bytes[i + 2] = clampByte(c.z); bytes[i + 3] = 255
            }
        }
        let image = makeLinearImage(bytes: bytes, width: width, height: height)

        // 프레임 사이 베이스 띠 = 정상 픽.
        guard let picked = FilmBasePicker.sample(in: image, atUnit: CGPoint(x: 0.5, y: 0.50)) else {
            return XCTFail("베이스 띠는 픽 되어야 한다.")
        }
        XCTAssertEqual(picked.x, base.x, accuracy: 0.03)
        XCTAssertEqual(picked.y, base.y, accuracy: 0.03)
        XCTAssertEqual(picked.z, base.z, accuracy: 0.03)

        XCTAssertNil(FilmBasePicker.sample(in: image, atUnit: CGPoint(x: 0.5, y: 0.05)),
                     "미조사 검정 띠는 베이스가 아니다.")
        XCTAssertNil(FilmBasePicker.sample(in: image, atUnit: CGPoint(x: 0.5, y: 0.95)),
                     "미조사 검정 띠는 베이스가 아니다.")
        XCTAssertNil(FilmBasePicker.sample(in: image, atUnit: CGPoint(x: 0.10, y: 0.50)),
                     "빈 베드(무필름 백라이트)는 베이스가 아니다.")
        XCTAssertNil(FilmBasePicker.sample(in: image, atUnit: CGPoint(x: 0.5, y: 0.35)),
                     "프레임 안 장면은 베이스보다 어둡다 — 베이스가 아니다.")
    }

    // MARK: base 실측의 인코딩 도메인 불변 (2026-07-16)

    private func srgbEncode(_ v: Double) -> Double {
        v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1.0 / 2.4) - 0.055
    }

    private func makeSRGBImage(bytes: [UInt8], width: Int, height: Int) -> CIImage {
        var mutable = bytes
        let cg = CGContext(data: &mutable, width: width, height: height,
                           bitsPerComponent: 8, bytesPerRow: width * 4,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        return CIImage(cgImage: cg)
    }

    /// 같은 물리 네거티브를 linear/sRGB 태그로 만들었을 때, autoLevels+autoNeutralBalance 를
    /// 켠 develop 결과가 인코딩 무관 동일해야 한다. 과거엔 측정 percentile/median 도메인이
    /// 입력 태그(sampleColorSpace)에 끌려가 sRGB 태그 입력에서 블랙포인트가 sRGB 값으로
    /// 측정돼 linear 스트레치에서 섀도 크러시 + 감마 과보정이 생겼다(2026-07-18 수정).
    func testAutoCorrectionsAreEncodingInvariantAcrossLinearAndSRGBInputs() throws {
        let width = 320, height = 200
        let trueBase = SIMD3<Double>(0.72, 0.46, 0.28)
        let bx = Int(Double(width) * 0.08), by = Int(Double(height) * 0.08)
        // float 픽스처 — 8bit linear 는 고밀도 영역(byte 1~5)이 양자화돼 두 인코딩의 실질
        // 데이터 자체가 달라진다(파이프라인 불변성이 아니라 입력 손실을 재게 됨).
        var linearFloats = [Float](repeating: 0, count: width * height * 4)
        var srgbFloats = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let isBorder = x < bx || x >= width - bx || y < by || y >= height - by
                let density = isBorder ? 0.0 : 0.3 + 1.1 * Double(x) / Double(width - 1)
                let rgb = trueBase * pow(10.0, -density)
                linearFloats[i] = Float(rgb.x); linearFloats[i + 1] = Float(rgb.y)
                linearFloats[i + 2] = Float(rgb.z); linearFloats[i + 3] = 1
                srgbFloats[i] = Float(srgbEncode(rgb.x)); srgbFloats[i + 1] = Float(srgbEncode(rgb.y))
                srgbFloats[i + 2] = Float(srgbEncode(rgb.z)); srgbFloats[i + 3] = 1
            }
        }
        func makeFloatImage(_ floats: [Float], colorSpace: CGColorSpace) -> CIImage {
            CIImage(
                bitmapData: Data(bytes: floats, count: floats.count * MemoryLayout<Float>.size),
                bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                size: CGSize(width: width, height: height),
                format: .RGBAf,
                colorSpace: colorSpace
            )
        }
        let linearImage = makeFloatImage(linearFloats, colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)
        let srgbImage = makeFloatImage(srgbFloats, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)

        var params = DevelopParameters()
        params.filmType = .colorNegative
        params.developTarget = .main
        params.autoLevels = true
        params.autoNeutralBalance = true
        let base = FilmBase(rgb: trueBase, source: .border)
        let engine = ChromabaseEngine()
        let outLinear = renderLinearRGBA8(
            engine.develop(image: linearImage, base: base, params: params),
            width: width, height: height)
        let outSRGB = renderLinearRGBA8(
            engine.develop(image: srgbImage, base: base, params: params),
            width: width, height: height)

        // 미드/섀도 대역 luma 가 인코딩 무관 일치해야 한다(8bit 입력 양자화 여유 ±6).
        let midY = height / 2
        for x in stride(from: bx + 8, to: width - bx - 8, by: 24) {
            let i = (midY * width + x) * 4
            let lumaLin = 0.2126 * Double(outLinear[i]) + 0.7152 * Double(outLinear[i + 1])
                + 0.0722 * Double(outLinear[i + 2])
            let lumaSRGB = 0.2126 * Double(outSRGB[i]) + 0.7152 * Double(outSRGB[i + 1])
                + 0.0722 * Double(outSRGB[i + 2])
            XCTAssertEqual(lumaSRGB, lumaLin, accuracy: 6.0,
                "sRGB 태그 입력의 자동 보정 결과가 linear 태그와 다르다(x=\(x)). " +
                "측정 도메인이 입력 태그에 끌려가면 안 된다.")
        }
    }

    /// 같은 물리 네거티브(linear 투과율)를 (a) linear 태그, (b) sRGB 태그(감마 인코딩 바이트)로
    /// 만들었을 때 자동 추정과 수동 스포이드 스냅이 동일한 linear Dmin 을 돌려줘야 한다.
    /// 과거에는 FilmBaseSampleGrid 가 비색관리(raw 직독)라 (b)에서 감마 값이 그대로 base 로
    /// 새어(linear 0.28 → 0.56) 가져오기/시뮬레이터 파일이 하얗고 파랗게 반전됐다
    /// (프로필 없는 스캐너 raw 는 linear 태그라 우연히 정상이었다).
    func testBaseMeasurementIsEncodingInvariantAcrossLinearAndSRGBInputs() throws {
        let width = 640, height = 480
        let trueBase = SIMD3<Double>(0.28, 0.18, 0.10)
        let bx = Int(Double(width) * 0.08), by = Int(Double(height) * 0.08)
        var linearBytes = [UInt8](repeating: 0, count: width * height * 4)
        var srgbBytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let isBorder = x < bx || x >= width - bx || y < by || y >= height - by
                let density = isBorder ? 0.0 : 0.4 + 1.2 * Double(x) / Double(width - 1)
                let atten = pow(10.0, -density)
                let rgb = trueBase * atten
                linearBytes[i]     = clampByte(rgb.x)
                linearBytes[i + 1] = clampByte(rgb.y)
                linearBytes[i + 2] = clampByte(rgb.z)
                linearBytes[i + 3] = 255
                srgbBytes[i]     = clampByte(srgbEncode(rgb.x))
                srgbBytes[i + 1] = clampByte(srgbEncode(rgb.y))
                srgbBytes[i + 2] = clampByte(srgbEncode(rgb.z))
                srgbBytes[i + 3] = 255
            }
        }
        let linearImage = makeLinearImage(bytes: linearBytes, width: width, height: height)
        let srgbImage = makeSRGBImage(bytes: srgbBytes, width: width, height: height)

        // 자동 추정: 두 인코딩 모두 실제 linear Dmin 으로 수렴해야 한다.
        let estLinear = try XCTUnwrap(FilmBaseEstimator.estimate(from: linearImage))
        let estSRGB = try XCTUnwrap(FilmBaseEstimator.estimate(from: srgbImage))
        for c in 0..<3 {
            XCTAssertEqual(estSRGB.rgb[c], estLinear.rgb[c], accuracy: 0.02,
                           "sRGB 인코딩 입력의 자동 추정이 linear 입력과 달라짐 (채널 \(c))")
            XCTAssertEqual(estLinear.rgb[c], trueBase[c], accuracy: 0.03,
                           "자동 추정이 linear Dmin 이 아님 (채널 \(c))")
        }

        // 수동 스포이드 스냅 경로(과거 비색관리 그리드를 쓰던 경로): 베이스 보더 클릭.
        let snapLinear = try XCTUnwrap(FilmBasePicker.snapToBase(
            in: linearImage, centerX: CGFloat(bx) / 2, centerY: CGFloat(height) / 2,
            neutralBase: false))
        let snapSRGB = try XCTUnwrap(FilmBasePicker.snapToBase(
            in: srgbImage, centerX: CGFloat(bx) / 2, centerY: CGFloat(height) / 2,
            neutralBase: false))
        for c in 0..<3 {
            XCTAssertEqual(snapSRGB[c], snapLinear[c], accuracy: 0.02,
                           "sRGB 인코딩 입력의 스포이드 스냅이 linear 입력과 달라짐 (채널 \(c))")
            XCTAssertEqual(snapLinear[c], trueBase[c], accuracy: 0.03,
                           "스포이드 스냅이 linear Dmin 이 아님 (채널 \(c))")
        }
    }
}
