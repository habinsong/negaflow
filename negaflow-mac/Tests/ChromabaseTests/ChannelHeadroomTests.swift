import CoreGraphics
import CoreImage
import XCTest
@testable import Chromabase

/// 자동 톤의 채널 한도(ChannelHeadroom, 2026-11-08): 휘도 목표가 채도 높은 색의 최대 채널을 1 위로 밀지
/// 않는다. 합성 장면을 실제 현상 경로(노출 숄더 → 기본 톤 커널 → 표시 경계)로 그려 잰다.
final class ChannelHeadroomTests: XCTestCase {
    private let engine = ChromabaseEngine()

    private func develop(_ image: CIImage, _ d: AutoAdjust.ToneDelta = .init()) -> CGImage {
        var p = DevelopParameters()
        p.filmType = .colorPositive
        p.exposure = d.exposure; p.contrast = d.contrast; p.density = d.density
        p.highlight = d.highlight; p.shadow = d.shadow; p.whites = d.whites; p.blacks = d.blacks
        let out = DisplayGamutMap.apply(to: engine.developScanner(image: image, base: nil, params: p))
        return ChromabaseEngine.sharedLinearRenderContext.createCGImage(
            out, from: out.extent, format: .RGBA8, colorSpace: SyntheticScan.srgb)!
    }

    /// 중립 현상본에서 1 에 닿지 않던 칸 중 조정 뒤에 닿은 칸의 비율.
    private func induced(_ neutral: CGImage, _ adjusted: CGImage) throws -> Double {
        let a = try XCTUnwrap(SceneAnalysisSampler.sample(CIImage(cgImage: neutral), longEdge: 200)).pixels
        let b = try XCTUnwrap(SceneAnalysisSampler.sample(CIImage(cgImage: adjusted), longEdge: 200)).pixels
        XCTAssertEqual(a.count, b.count)
        func peak(_ p: SIMD3<Double>) -> Double { max(p.x, max(p.y, p.z)) }
        let count = zip(a, b).filter { peak($0.0) < ChannelHeadroom.clipLevel && peak($0.1) >= ChannelHeadroom.clipLevel }.count
        return Double(count) / Double(a.count)
    }

    private func lumaOnly(_ s: AutoAdjust.ImageStats) -> AutoAdjust.ImageStats {
        var copy = s
        copy.peakSamples = []
        return copy
    }

    /// 채도 높은 빨강(선형 0.40, 0.03, 0.03 — 휘도 0.11)이 화면 25% 인 장면. 휘도로는 명부 여유가 3 스톱이라 예전 노출은
    /// 키까지 밝혀 빨강 전체의 R 을 1 에 붙였다. 지키는 데 1 스톱(channelExposureBudget) 안이면 노출은 빨강이 닿기 직전에서
    /// 멈추고 모자란 중간톤은 농도가 채운다. 더 어두운 장면이라 1 스톱보다 더 내려야 하면 1 스톱만 내주고 클리핑을
    /// 받아들인다.
    func testExposureStopsBeforeSaturatedMidtonesClip() throws {
        func scene(_ darkest: Double, _ brightest: Double) -> CIImage {
            SyntheticScan.makeImage(width: 400, height: 200) { x, y in
                if y < 50 { return SIMD3(0.40, 0.03, 0.03) }
                return SIMD3(repeating: darkest + (brightest - darkest) * Double(x) / 400)
            }
        }
        let image = scene(0.03, 0.16)
        let neutral = develop(image)
        let stats = try XCTUnwrap(AutoAdjust.imageStats(neutral))
        XCTAssertFalse(stats.peakSamples.isEmpty)
        let lumaProposal = AutoAdjust.autoTone(lumaOnly(stats), filmType: .colorPositive)
        XCTAssertGreaterThan(try induced(neutral, develop(image, lumaProposal)), 0.10,
                             "장면이 시험하려는 상황이 아니다(휘도만 보는 제안이 빨강을 밀지 않는다)")
        let auto = AutoAdjust.autoTone(stats, filmType: .colorPositive)
        XCTAssertLessThanOrEqual(try induced(neutral, develop(image, auto)), ChannelHeadroom.allowance + 0.002,
                                 "ev=\(auto.exposure) luma=\(lumaProposal.exposure)")
        XCTAssertGreaterThan(auto.exposure, 0.5, "노출을 통째로 버렸다")
        XCTAssertLessThan(auto.exposure, lumaProposal.exposure)
        XCTAssertGreaterThan(auto.exposure, lumaProposal.exposure - AutoAdjust.channelExposureBudget)
        XCTAssertLessThan(auto.density, 0, "노출이 막힌 만큼 중간톤을 농도로 채운다")

        let dim = scene(0.01, 0.10)
        let dimStats = try XCTUnwrap(AutoAdjust.imageStats(develop(dim)))
        let dimLuma = AutoAdjust.autoTone(lumaOnly(dimStats), filmType: .colorPositive)
        XCTAssertGreaterThan(dimLuma.exposure - log2(ChannelHeadroom.safeLevel / 0.40), AutoAdjust.channelExposureBudget,
                             "보호에 1 스톱보다 더 필요한 장면이어야 한다")
        let dimAuto = AutoAdjust.autoTone(dimStats, filmType: .colorPositive)
        XCTAssertEqual(dimAuto.exposure, dimLuma.exposure - AutoAdjust.channelExposureBudget, accuracy: 0.01)
    }

    /// 밝은 장면의 노란 면(선형 0.80, 0.70, 0.08 — 휘도 0.68, 화면 3%)은 휘도 백점이다. 흰색이 휘도를 확산
    /// 화이트(0.90)로 올리면 R 이 1 을 넘었다. 이제 흰색은 노랑이 닿기 직전까지만 올린다.
    func testWhitesStopAtTheChannelClipPoint() throws {
        let width = 400, height = 200
        let image = SyntheticScan.makeImage(width: width, height: height) { x, y in
            if y < 6 { return SIMD3(0.80, 0.70, 0.08) }
            return SIMD3(repeating: 0.05 + 0.50 * Double(x) / Double(width))
        }
        let neutral = develop(image)
        let stats = try XCTUnwrap(AutoAdjust.imageStats(neutral))

        let lumaProposal = AutoAdjust.autoTone(lumaOnly(stats), filmType: .colorPositive)
        XCTAssertGreaterThan(lumaProposal.whites, 0)
        XCTAssertGreaterThan(try induced(neutral, develop(image, lumaProposal)), 0.02)

        let auto = AutoAdjust.autoTone(stats, filmType: .colorPositive)
        XCTAssertLessThanOrEqual(try induced(neutral, develop(image, auto)), ChannelHeadroom.allowance + 0.002,
                                 "wh=\(auto.whites) ev=\(auto.exposure)")
        XCTAssertGreaterThan(auto.whites, 0, "흰색을 통째로 버렸다")
        // 가장 큰 흰색이다 — 조금만 더 올려도 한도를 넘는다.
        var more = auto
        more.whites += 0.02
        XCTAssertGreaterThan(ChannelHeadroom.inducedClipping(stats.peakSamples, total: stats.peakSamples.count, more,
                                                             filmType: .colorPositive),
                             ChannelHeadroom.allowance)
    }

    /// 예측은 실제 커널과 맞는다 — 노출·흰색·농도·대비·명부를 섞은 값에서 칸마다 최대 채널이 같다.
    func testPredictionMatchesTheRenderedKernels() throws {
        let width = 480, height = 240
        let colors: [SIMD3<Double>] = [
            SIMD3(0.40, 0.03, 0.03), SIMD3(0.80, 0.70, 0.08), SIMD3(0.05, 0.30, 0.60), SIMD3(0.55, 0.50, 0.45),
        ]
        let image = SyntheticScan.makeImage(width: width, height: height) { x, y in
            let scale = 0.25 + 0.75 * Double(x) / Double(width)
            return colors[min(colors.count - 1, y * colors.count / height)] * scale
        }
        let neutral = develop(image)
        let before = try XCTUnwrap(SceneAnalysisSampler.sample(CIImage(cgImage: neutral), longEdge: 200)).pixels
        for (ev, whites, density, contrast, highlight) in [
            (0.6, 0.0, 0.0, 0.0, 0.0), (0.4, 0.6, 0.0, 0.0, 0.0), (0.0, 0.8, -0.4, 0.3, 0.0), (1.0, 0.3, 0.0, 0.0, -0.6),
            (-0.5, 0.5, 0.0, -0.15, 0.0),
        ] {
            var d = AutoAdjust.ToneDelta()
            d.exposure = ev; d.whites = whites; d.density = density; d.contrast = contrast; d.highlight = highlight
            let after = try XCTUnwrap(SceneAnalysisSampler.sample(CIImage(cgImage: develop(image, d)), longEdge: 200)).pixels
            XCTAssertEqual(before.count, after.count)
            var worst = 0.0
            for (a, b) in zip(before, after) {
                let predicted = ChannelHeadroom.predictedPeak(ChannelHeadroom.sample(a), d, filmType: .colorPositive)
                worst = max(worst, abs(predicted - max(b.x, max(b.y, b.z))))
            }
            // 8 비트 표본의 명부 한 코드(선형 0.009)보다 작다 — safeLevel 의 여유(0.015)가 덮는다.
            XCTAssertLessThan(worst, 0.009, "\(d)")
        }
    }

    /// 미리 거른 표본으로 센 값은 전체 표본으로 센 값과 같다(자동 톤이 쓰는 노출·리프트 범위 안).
    func testCandidatePruningKeepsTheCount() throws {
        let width = 480, height = 240
        let image = SyntheticScan.makeImage(width: width, height: height) { x, y in
            let t = Double(x) / Double(width), band = y * 6 / height
            let colors: [SIMD3<Double>] = [SIMD3(0.9, 0.1, 0.05), SIMD3(0.7, 0.65, 0.1), SIMD3(0.1, 0.4, 0.8),
                                           SIMD3(0.5, 0.5, 0.5), SIMD3(0.95, 0.9, 0.85), SIMD3(0.2, 0.6, 0.2)]
            return colors[band] * (0.05 + 0.95 * t)
        }
        let stats = try XCTUnwrap(AutoAdjust.imageStats(develop(image)))
        let candidates = ChannelHeadroom.candidates(stats.peakSamples, maxStops: 1.5, maxLift: ChannelHeadroom.maximumAutoLift)
        XCTAssertLessThan(candidates.count, stats.peakSamples.count)
        for (ev, contrast, density, shadow, whites, blacks) in [
            (1.5, 0.55, -0.4, 0.8, 1.0, 0.15), (0.7, 0.2, -0.2, 0.3, 0.5, 0.0), (0.0, -0.15, 0.0, 0.0, 1.0, -1.0),
            (-1.0, 0.55, -0.4, 0.8, 1.0, 0.15),
        ] {
            var d = AutoAdjust.ToneDelta()
            d.exposure = ev; d.contrast = contrast; d.density = density; d.shadow = shadow; d.whites = whites; d.blacks = blacks
            XCTAssertEqual(
                ChannelHeadroom.inducedClipping(candidates, total: stats.peakSamples.count, d, filmType: .colorPositive),
                ChannelHeadroom.inducedClipping(stats.peakSamples, total: stats.peakSamples.count, d, filmType: .colorPositive),
                "\(d)")
        }
    }

    /// 폐루프의 실측은 화소 단위다: 한 화소 건너 채도 높은 질감(꽃잎·잎사귀 같은)은 칸 평균에서는 1 에 못 닿아도 화소는
    /// 255 에 닿는다. 칸으로만 세면 이 클리핑이 묻힌다. 같은 무늬가 무채색이면 휘도가 확산 화이트를 넘는 반사광이라
    /// 세지 않는다.
    func testMeasuredClippingCountsPixelsNotCellAverages() throws {
        func checker(_ bright: SIMD3<Double>, _ dark: SIMD3<Double>) -> CIImage {
            SyntheticScan.makeImage(width: 400, height: 200) { x, y in (x + y) % 2 == 0 ? bright : dark }
        }
        let image = checker(SIMD3(0.985, 0.45, 0.05), SIMD3(0.45, 0.20, 0.02))
        let neutral = try XCTUnwrap(AutoAdjust.imageStats(develop(image)))
        var brighter = AutoAdjust.ToneDelta()
        brighter.exposure = 0.15
        let measured = try XCTUnwrap(AutoAdjust.imageStats(develop(image, brighter)))
        XCTAssertEqual(ChannelHeadroom.measuredInducedClipping(neutral: neutral.peakSamples,
                                                               measured: measured.peakSamples) ?? 1, 0,
                       "칸 평균은 닿지 않는다")
        let pixels = try XCTUnwrap(ChannelHeadroom.measuredInducedClipping(neutral: neutral, measured: measured))
        XCTAssertGreaterThan(pixels, 0.4, "화소의 절반이 255 에 닿는다")
        XCTAssertGreaterThan(AutoAdjust.channelExcess(neutral: neutral, measured: measured) ?? 0, 0)

        let specular = checker(SIMD3(repeating: 0.97), SIMD3(repeating: 0.55))
        var whites = AutoAdjust.ToneDelta()
        whites.whites = 0.6
        let specularNeutral = try XCTUnwrap(AutoAdjust.imageStats(develop(specular)))
        let specularMeasured = try XCTUnwrap(AutoAdjust.imageStats(develop(specular, whites)))
        XCTAssertGreaterThan(specularMeasured.pixelPeaks.filter { $0 == 255 }.count, specularMeasured.pixelPeaks.count / 3)
        XCTAssertEqual(ChannelHeadroom.measuredInducedClipping(neutral: specularNeutral, measured: specularMeasured) ?? 1, 0,
                       "확산 화이트 위의 무채색은 날아가도 된다")
    }

    /// 맥·윈도우가 같은 통계에서 같은 값을 내는지 보는 고정 통계(`channel_headroom_tests.cpp` 와 같은 식으로 만든다):
    /// 어두운 회색 600 칸, 채도 높은 빨강 250 칸(휘도 인코딩 95, R 0.75), 노랑 140 칸(205, 0.90), 명부 10 칸(230, 0.86).
    static func parityFixture() -> AutoAdjust.ImageStats {
        func decode(_ code: Double) -> Double { AutoAdjust.srgbDecode(code / 255) }
        var samples: [SIMD2<Double>] = (0..<600).map { k in
            let v = decode(Double(20 + k % 60)); return SIMD2(v, v)
        }
        samples += Array(repeating: SIMD2(decode(95), 0.75), count: 250)
        samples += Array(repeating: SIMD2(decode(205), 0.90), count: 140)
        samples += Array(repeating: SIMD2(decode(230), 0.86), count: 10)
        var hist = [Double](repeating: 0, count: 256)
        for sample in samples {
            hist[min(255, Int((AutoAdjust.srgbEncode(sample.x) * 255).rounded()))] += 1.0 / Double(samples.count)
        }
        var stats = AutoAdjust.ImageStats(avgR: 0.3, avgG: 0.3, avgB: 0.3, lumaHist: hist, avgSaturation: 0.3)
        stats.peakSamples = samples
        return stats
    }

    /// 같은 고정 통계에서 맥과 윈도우(`test_channel_guard_matches_macos`)가 같은 값을 낸다. 채널 한도가 노출을
    /// 0.638 → 0.335 로 줄이고 농도·흰색·검정을 그 노출로 다시 푸는 경로다.
    func testChannelGuardParityFixture() {
        let t = AutoAdjust.autoTone(Self.parityFixture(), filmType: .colorNegative)
        XCTAssertEqual(t.exposure, 0.335171208, accuracy: 1e-6)
        XCTAssertEqual(t.contrast, -0.15, accuracy: 1e-6)
        XCTAssertEqual(t.density, -0.4, accuracy: 1e-6)
        XCTAssertEqual(t.highlight, 0, accuracy: 1e-6)
        XCTAssertEqual(t.shadow, 0, accuracy: 1e-6)
        XCTAssertEqual(t.whites, -0.045220701, accuracy: 1e-6)
        XCTAssertEqual(t.blacks, -0.588419083, accuracy: 1e-6)
    }

    /// 폐루프의 더 밝히는 몫: 중립 현상본이 없으면 잰 클리핑(원본에서 날아간 1%)을 모두 이미 쓴 몫으로 봐 새 클리핑을
    /// 하나도 만들지 않는 데까지(0.4% 의 R 0.90 화소가 정한다), 중립 현상본이 있으면 실제로 새로 날아간 몫(0)을 뺀
    /// 0.5% 까지 밝힌다(그때는 화면 30% 의 R 0.70 이 정한다).
    func testRefineToneRaisesOnlyWithinTheChannelBudget() {
        var hist = [Double](repeating: 0, count: 256)
        hist[30] = 0.686; hist[100] = 0.30; hist[150] = 0.004; hist[255] = 0.01
        var stats = AutoAdjust.ImageStats(avgR: 0.2, avgG: 0.2, avgB: 0.2, lumaHist: hist, avgSaturation: 0.3)
        func d(_ code: Double) -> Double { AutoAdjust.srgbDecode(code / 255) }
        stats.peakSamples = Array(repeating: SIMD2(d(30), d(30)), count: 686)
            + Array(repeating: SIMD2(d(100), 0.70), count: 300) + Array(repeating: SIMD2(d(150), 0.90), count: 4)
            + Array(repeating: SIMD2(1.0, 1.0), count: 10)
        stats.clippedFraction = 0.01
        let first = AutoAdjust.ToneDelta()
        var unbounded = stats
        unbounded.peakSamples = []
        XCTAssertGreaterThan(AutoAdjust.refineTone(first, measured: unbounded, filmType: .colorPositive).exposure, 1.0,
                             "키가 노출을 크게 올리는 장면이어야 한다")
        let blind = AutoAdjust.refineTone(first, measured: stats, filmType: .colorPositive)
        XCTAssertEqual(blind.exposure, log2(ChannelHeadroom.ceiling(above: 0.90) / 0.90), accuracy: 0.01)
        // 중립 현상본이 있으면 폐루프 한 번은 키 보정을 그대로 내고, 넘치는지는 그린 결과로 이분한다.
        let aware = AutoAdjust.refineTone(first, measured: stats, neutral: stats, filmType: .colorPositive)
        XCTAssertEqual(aware.exposure, AutoAdjust.refineTone(first, measured: unbounded, filmType: .colorPositive).exposure,
                       accuracy: 1e-9)
        // 그린 결과(모형 그대로)로 이분하면 R 0.70 이 한도에 닿기 직전에서 멈춘다(화면 30% 가 한꺼번에 넘으므로).
        func render(_ delta: AutoAdjust.ToneDelta) -> AutoAdjust.ImageStats {
            let gain = pow(2, delta.exposure)
            let samples = stats.peakSamples.map { sample in
                sample.y >= ChannelHeadroom.clipLevel ? sample : SIMD2(min(sample.x * gain, 1), min(sample.y * gain, 1))
            }
            var hist = [Double](repeating: 0, count: 256)
            for sample in samples {
                hist[min(255, Int((AutoAdjust.srgbEncode(sample.x) * 255).rounded()))] += 1 / Double(samples.count)
            }
            var rendered = AutoAdjust.ImageStats(avgR: 0.2, avgG: 0.2, avgB: 0.2, lumaHist: hist, avgSaturation: 0.3)
            rendered.peakSamples = samples
            rendered.clippedFraction = Double(samples.filter { $0.y >= ChannelHeadroom.clipLevel }.count) / Double(samples.count)
            return rendered
        }
        let chosen = AutoAdjust.closedLoopTone(first, measured: stats, neutral: stats, filmType: .colorPositive,
                                               measure: render)
        XCTAssertEqual(AutoAdjust.channelExcess(neutral: stats, measured: render(chosen)) ?? 1, 0)
        XCTAssertGreaterThan(chosen.exposure, 0.25, "맞는 만큼은 밝힌다")
        XCTAssertLessThan(chosen.exposure, log2(ChannelHeadroom.clipLevel / 0.70))
    }

    /// 모형 밖 단계(스캐너 타깃 같은)가 확인 렌더에서 밝은 노랑을 1 에 붙이면, 폐루프는 그 칸의 잰 값으로 예측을
    /// 바로잡아 흰색부터 거두고 모자라면 노출을 낮춘다. 1 에 묶인 칸은 잰 값이 하한이라, 앱처럼 다시 그려 거두기를
    /// 되풀이하면(최대 channelRefinementLimit 회) 한도 안으로 들어온다. 후보 선택은 한도 초과가 적은 쪽을 먼저 고른다.
    func testRefineToneWithdrawsWhatTheRenderedTargetClips() {
        func stats(_ samples: [SIMD2<Double>]) -> AutoAdjust.ImageStats {
            var hist = [Double](repeating: 0, count: 256)
            for sample in samples {
                hist[min(255, Int((AutoAdjust.srgbEncode(min(sample.x, 1)) * 255).rounded()))] += 1 / Double(samples.count)
            }
            var result = AutoAdjust.ImageStats(avgR: 0.3, avgG: 0.3, avgB: 0.3, lumaHist: hist, avgSaturation: 0.3)
            result.peakSamples = samples
            result.clippedFraction = Double(samples.filter { $0.y >= ChannelHeadroom.clipLevel }.count) / Double(samples.count)
            return result
        }
        let neutralSamples = Array(repeating: SIMD2(0.20, 0.20), count: 900) + Array(repeating: SIMD2(0.60, 0.80), count: 100)
        let neutral = stats(neutralSamples)
        // 모형 밖 단계: 노랑에서 톤이 움직인 양을 60% 더 키운다(중립에서는 정의상 0).
        func render(_ delta: AutoAdjust.ToneDelta) -> AutoAdjust.ImageStats {
            stats(neutralSamples.map { n in
                let peak = ChannelHeadroom.predictedPeak(n, delta, filmType: .colorPositive)
                return SIMD2(n.x, n.y > 0.5 ? min(peak + 0.6 * (peak - n.y), 1) : peak)
            })
        }
        var first = AutoAdjust.ToneDelta()
        first.exposure = 0.3; first.whites = 0.4
        let measured = render(first)
        XCTAssertGreaterThan(AutoAdjust.channelExcess(neutral: neutral, measured: measured) ?? 0, 0.05)
        // 한 번의 모형 보정은 1 에 묶인 칸 때문에 덜 거둔다 — 그래도 흰색부터 내린다.
        let refined = AutoAdjust.refineTone(first, measured: measured, neutral: neutral, filmType: .colorPositive)
        XCTAssertLessThan(refined.whites, first.whites)
        XCTAssertTrue(AutoAdjust.prefersCandidate(render(refined), over: measured, neutral: neutral)
                      || AutoAdjust.channelExcess(neutral: neutral, measured: render(refined)) ==
                         AutoAdjust.channelExcess(neutral: neutral, measured: measured))
        var renders = 0
        let chosen = AutoAdjust.closedLoopTone(first, measured: measured, neutral: neutral, filmType: .colorPositive) {
            renders += 1
            return render($0)
        }
        XCTAssertEqual(AutoAdjust.channelExcess(neutral: neutral, measured: render(chosen)) ?? 1, 0, "\(chosen)")
        XCTAssertLessThanOrEqual(renders, 1 + AutoAdjust.channelRefinementLimit)
        XCTAssertGreaterThan(chosen.exposure + chosen.whites, 0, "밝히는 몫을 통째로 버렸다")
        XCTAssertFalse(AutoAdjust.prefersCandidate(measured, over: render(chosen), neutral: neutral))
    }

    /// 폐루프가 채널을 지키느라 어둡게 하는 몫은 잰 장면 키로 묶인다: 모형 밖 단계(스캐너 타깃의 암부 톤 곡선 같은)가
    /// 노출 변화를 두 배로 키우면, 노출 바닥(1 스톱)까지 내려가 등불을 지키는 점은 키가 2 스톱 어둡다. 폐루프는 그 점을
    /// 고르지 않고 확인 렌더의 키에서 남은 예산(1 스톱) 안에 머문다 — 그 아래까지 내려야 맞는 장면이면 클리핑을 받아들인다.
    func testClosedLoopDarkensTheMeasuredKeyByAtMostTheBudget() throws {
        func stats(_ samples: [SIMD2<Double>]) -> AutoAdjust.ImageStats {
            var hist = [Double](repeating: 0, count: 256)
            for sample in samples {
                hist[min(255, Int((AutoAdjust.srgbEncode(min(sample.x, 1)) * 255).rounded()))] += 1 / Double(samples.count)
            }
            var result = AutoAdjust.ImageStats(avgR: 0.3, avgG: 0.3, avgB: 0.3, lumaHist: hist, avgSaturation: 0.3)
            result.peakSamples = samples
            result.clippedFraction = Double(samples.filter { $0.y >= ChannelHeadroom.clipLevel }.count) / Double(samples.count)
            return result
        }
        // 어두운 장면(회색 0.002~0.008)에 채도 높은 등불 3%(휘도 0.04, R 0.21).
        var neutralSamples: [SIMD2<Double>] = []
        for k in 0..<970 {
            let v: Double = 0.002 + 0.006 * Double(k) / 970
            neutralSamples.append(SIMD2(v, v))
        }
        neutralSamples += Array(repeating: SIMD2<Double>(0.04, 0.21), count: 30)
        let neutral = stats(neutralSamples)
        // 모형 밖 단계: 회색의 휘도는 노출의 두 배로 움직이고, 등불은 노출 이득 그대로다.
        func render(_ delta: AutoAdjust.ToneDelta) -> AutoAdjust.ImageStats {
            let grayGain = pow(2, 2 * delta.exposure), gain = pow(2, delta.exposure)
            return stats(neutralSamples.map { n -> SIMD2<Double> in
                n.y > n.x * 2 ? SIMD2(min(n.x * gain, 1), min(n.y * gain, 1))
                              : SIMD2(min(n.x * grayGain, 1), min(n.y * grayGain, 1))
            })
        }
        var luminanceOnly = neutral
        luminanceOnly.peakSamples = []
        let first = AutoAdjust.autoTone(luminanceOnly, filmType: .colorPositive)   // 첫 계산이 등불을 못 본 경우
        XCTAssertGreaterThan(first.exposure, 2.0)
        let measured = render(first)
        XCTAssertGreaterThan(AutoAdjust.channelExcess(neutral: neutral, measured: measured) ?? 0, 0)
        let floor = measured.logAverageLuminance
            * pow(2, -AutoAdjust.remainingKeyBudget(first: first, neutral: neutral, filmType: .colorPositive))
        // 키 바닥이 없으면 이분은 등불이 맞는 점까지 내려가 키를 바닥보다 어둡게 만든다.
        var bottom = first
        bottom.exposure = first.exposure - AutoAdjust.channelExposureBudget
        bottom.whites = min(first.whites, 0)
        let unbounded = AutoAdjust.bisectChannels(from: bottom, to: first, exceedingStats: measured, neutral: neutral,
                                                  keyFloor: 0, measure: render)
        let darkest = try XCTUnwrap(unbounded.fit)
        XCTAssertLessThan(darkest.stats.logAverageLuminance, floor)
        let chosen = AutoAdjust.closedLoopTone(first, measured: measured, neutral: neutral, filmType: .colorPositive,
                                               measure: render)
        XCTAssertGreaterThanOrEqual(render(chosen).logAverageLuminance, floor * (1 - 1e-9), "\(chosen)")
    }

    /// 채널 한도를 넘지 않는 장면에서 폐루프는 예전과 같다(중립 현상본이 있어도 추가 렌더가 없다).
    func testClosedLoopAddsNoRenderWhenChannelsFit() {
        var hist = [Double](repeating: 0, count: 256)
        hist[90] = 0.5; hist[160] = 0.5
        var stats = AutoAdjust.ImageStats(avgR: 0.3, avgG: 0.3, avgB: 0.3, lumaHist: hist, avgSaturation: 0.1)
        stats.peakSamples = Array(repeating: SIMD2(AutoAdjust.srgbDecode(90.0 / 255), AutoAdjust.srgbDecode(90.0 / 255)), count: 50)
            + Array(repeating: SIMD2(AutoAdjust.srgbDecode(160.0 / 255), AutoAdjust.srgbDecode(160.0 / 255)), count: 50)
        let first = AutoAdjust.autoTone(stats, filmType: .colorPositive)
        var renders = 0
        _ = AutoAdjust.closedLoopTone(first, measured: stats, neutral: stats, filmType: .colorPositive) { _ in
            renders += 1
            return stats
        }
        XCTAssertLessThanOrEqual(renders, 1)
    }
}
