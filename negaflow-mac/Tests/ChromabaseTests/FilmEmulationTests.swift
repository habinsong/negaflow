import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

// FilmEmulationStage 검증 — 데이터시트 사실을 측정으로 확인(합성 패치, 오버핏 방지).
//   • none / intensity 0 = 완전 항등
//   • Velvia: 채도·대비 큰 폭 증가(E100 보다), 딥 섀도우, 밝기대별 색 크로스오버
//   • E100: 절제된 채도 + 전 계조 뉴트럴(저대비)
//   • 채도 부스트는 여러 밝기에서 일관되게 동작(밝기 의존적 필름 응답)
final class FilmEmulationTests: XCTestCase {

    // MARK: 항등

    func testNoneIsIdentity() {
        let patch = solidRGB(0.4, 0.25, 0.15)
        assertEqualRGB(render(FilmEmulationStage.apply(to: patch, emulation: .none, intensity: 1.0)),
                       render(patch), accuracy: 1e-4)
    }

    func testIntensityZeroIsIdentity() {
        let patch = solidRGB(0.4, 0.25, 0.15)
        assertEqualRGB(render(FilmEmulationStage.apply(to: patch, emulation: .velvia50, intensity: 0)),
                       render(patch), accuracy: 1e-4)
    }

    // MARK: 채도

    func testBothFilmsBoostSaturationOnColoredPatch() {
        let green = solidRGB(0.14, 0.42, 0.16)
        let base = meanChroma(render(green))
        let e100 = meanChroma(render(FilmEmulationStage.apply(to: green, emulation: .ektachromeE100, intensity: 1)))
        let velvia = meanChroma(render(FilmEmulationStage.apply(to: green, emulation: .velvia50, intensity: 1)))
        XCTAssertGreaterThan(e100, base + 0.005, "E100 도 채도를 올려야 합니다(절제).")
        XCTAssertGreaterThan(velvia, base + 0.03, "Velvia 는 채도를 크게 올려야 합니다.")
    }

    func testVelviaMoreSaturatedThanE100() {
        let green = solidRGB(0.14, 0.42, 0.16)
        let e100 = meanChroma(render(FilmEmulationStage.apply(to: green, emulation: .ektachromeE100, intensity: 1)))
        let velvia = meanChroma(render(FilmEmulationStage.apply(to: green, emulation: .velvia50, intensity: 1)))
        XCTAssertGreaterThan(velvia, e100 + 0.03, "Velvia 채도 > E100 채도.")
    }

    /// 밝기가 달라도 채도 부스트가 일관되게 동작해야 한다(밝기 의존적 필름 응답).
    func testSaturationBoostConsistentAcrossBrightness() {
        for scale in [0.5, 1.0, 1.6] {
            let g = solidRGB(Float(0.10 * scale), Float(0.34 * scale), Float(0.12 * scale))
            let base = meanChroma(render(g))
            let velvia = meanChroma(render(FilmEmulationStage.apply(to: g, emulation: .velvia50, intensity: 1)))
            XCTAssertGreaterThan(velvia, base + 0.01, "밝기 \(scale) 에서도 Velvia 채도가 올라야 합니다.")
        }
    }

    // MARK: 대비 / 섀도우

    func testVelviaDeepensShadows() {
        let dark = solid(0.08)
        let base = meanLuma(render(dark))
        let velvia = meanLuma(render(FilmEmulationStage.apply(to: dark, emulation: .velvia50, intensity: 1)))
        XCTAssertLessThan(velvia, base - 0.01, "Velvia 는 섀도우를 더 깊게 크러시해야 합니다.")
    }

    /// Velvia 가 E100 보다 대비가 높다(밝은 패치 - 어두운 패치 휘도 스프레드가 더 큼).
    func testVelviaHigherContrastThanE100() {
        let dark = solid(0.16), light = solid(0.72)
        func spread(_ f: FilmEmulation) -> Double {
            let d = meanLuma(render(FilmEmulationStage.apply(to: dark, emulation: f, intensity: 1)))
            let l = meanLuma(render(FilmEmulationStage.apply(to: light, emulation: f, intensity: 1)))
            return l - d
        }
        XCTAssertGreaterThan(spread(.velvia50), spread(.ektachromeE100) + 0.02,
                             "Velvia 대비 > E100 대비.")
    }

    // MARK: 크로스오버 / 중립

    /// Velvia 채널 크로스오버 — 어두운 중립은 밝은 중립보다 상대적으로 쿨(B-R 가 더 큼).
    func testVelviaShadowsCoolerThanHighlights() {
        let darkGray = solid(0.14), lightGray = solid(0.68)
        let d = render(FilmEmulationStage.apply(to: darkGray, emulation: .velvia50, intensity: 1))
        let l = render(FilmEmulationStage.apply(to: lightGray, emulation: .velvia50, intensity: 1))
        XCTAssertGreaterThan((d.b - d.r), (l.b - l.r) + 0.004,
                             "Velvia 섀도우가 하이라이트보다 쿨(B-R 큼)해야 합니다.")
    }

    func testE100KeepsNeutralApproximatelyNeutral() {
        // "consistent gray scale rendition throughout the tonal range" — 여러 밝기에서 중립 유지.
        for v in [0.12, 0.35, 0.62] as [Float] {
            let out = render(FilmEmulationStage.apply(to: solid(v), emulation: .ektachromeE100, intensity: 1))
            XCTAssertLessThan(meanChroma(out), 0.02,
                              "E100 은 밝기 \(v) 중립 그레이를 크게 물들이면 안 됩니다.")
        }
    }

    func testE100TiltsCoolOnNeutral() {
        let out = render(FilmEmulationStage.apply(to: solid(0.4), emulation: .ektachromeE100, intensity: 1))
        XCTAssertGreaterThan(out.b, out.r + 0.002, "E100 은 중립을 미세하게 쿨(B>R)로 틸트해야 합니다.")
    }

    // MARK: intensity

    func testIntensityScalesMonotonically() {
        let green = solidRGB(0.14, 0.42, 0.16)
        let base = meanChroma(render(green))
        let half = meanChroma(render(FilmEmulationStage.apply(to: green, emulation: .velvia50, intensity: 0.5)))
        let full = meanChroma(render(FilmEmulationStage.apply(to: green, emulation: .velvia50, intensity: 1.0)))
        XCTAssertGreaterThan(half, base + 0.005, "intensity 0.5 는 원본보다 강해야 합니다.")
        XCTAssertGreaterThan(full, half + 0.005, "intensity 1.0 은 0.5 보다 강해야 합니다.")
    }

    // MARK: 목록 구성 (UI 계약)

    func testFilmListIsGroupedByFilmKindWithNoneFirst() {
        XCTAssertEqual(FilmEmulation.allCases.first, FilmEmulation.none)
        XCTAssertNil(FilmEmulation.none.kind)
        XCTAssertEqual(FilmEmulation.films(of: .slide), [
            .ektachromeE100, .provia100F, .velvia50, .velvia100, .e100VS, .astia100F, .kodachrome64,
        ])
        XCTAssertEqual(FilmEmulation.films(of: .negative), [
            .portra160, .portra400, .portra800, .ektar100,
            .ultramax400, .colorPlus200, .fujicolorC200, .pro400H,
            .gold200, .proImage100, .superia400, .superiaPremium400,
            .superia200, .reala100, .industrial100, .lomoCn800,
        ])
        XCTAssertEqual(FilmEmulation.films(of: .motionPicture), [
            .vision3_500T, .vision3_250D, .vision3_50D, .vision3_200T,
        ])
        XCTAssertEqual(FilmEmulation.films(of: .bwNegative), [
            .triX400, .hp5Plus, .fp4Plus, .delta100, .delta400, .delta3200,
            .tmax100, .tmax400, .tmaxP3200, .kentmere400, .orthoPlus, .sfx200, .rolleiIR,
        ])
        XCTAssertEqual(FilmEmulation.films(of: .bwReversal), [.scala200X, .rolleiSuperpan])
        // 모든 항목은 .none 을 빼면 반드시 한 그룹에 속한다(목록에서 누락되지 않는다).
        XCTAssertEqual(
            FilmEmulation.allCases.count,
            1 + FilmEmulation.films(of: .slide).count + FilmEmulation.films(of: .negative).count
                + FilmEmulation.films(of: .motionPicture).count
                + FilmEmulation.films(of: .bwNegative).count
                + FilmEmulation.films(of: .bwReversal).count
        )
    }

    func testDefaultIntensityIsHalf() {
        XCTAssertEqual(DevelopParameters().filmEmulationIntensity, 0.5, accuracy: 1e-9)
    }

    // MARK: 프로파일 불변식

    /// 색 매트릭스 행합=1 — 무채색을 물들이지 않는다는 모델의 전제. 새 필름을 넣을 때 가장 깨지기 쉽다.
    func testEveryProfileMatrixPreservesNeutrals() {
        for film in FilmEmulation.allCases {
            let p = FilmEmulationProfile.of(film)
            for (name, row) in [("R", p.mR), ("G", p.mG), ("B", p.mB)] {
                XCTAssertEqual(row.x + row.y + row.z, 1.0, accuracy: 1e-9,
                               "\(film.rawValue) m\(name) 행합이 1이 아닙니다.")
            }
            XCTAssertEqual(p.iieHue.count, 6, "\(film.rawValue) iieHue 앵커는 6개여야 합니다.")
        }
    }

    /// 네거티브는 필름 자체가 최종 결과물이 아니라 렌더된 응답을 모델링한다 — 슬라이드보다 대비가
    /// 낮고 토우가 들려(넓은 섀도우 관용도) 있어야 한다.
    func testNegativeProfilesAreFlatterAndLiftedComparedToSlides() {
        let slideContrast = FilmEmulation.films(of: .slide)
            .map { FilmEmulationProfile.of($0).toneG.contrast }
        let lowestSlideContrast = slideContrast.min() ?? 0
        for film in FilmEmulation.films(of: .negative) where film != .ektar100 {
            let p = FilmEmulationProfile.of(film)
            XCTAssertLessThanOrEqual(p.toneG.contrast, lowestSlideContrast,
                                     "\(film.rawValue) 는 슬라이드보다 대비가 높으면 안 됩니다.")
            XCTAssertLessThan(p.toneG.black, 0,
                              "\(film.rawValue) 는 토우가 들려 있어야 합니다(섀도우 관용도).")
        }
    }

    /// Portra 3형제: 160 → 400 → 800 순으로 대비·채도가 올라가고 언더 관용도(토우 리프트)도 커진다.
    func testPortraFamilyOrdering() {
        let p160 = FilmEmulationProfile.of(.portra160)
        let p400 = FilmEmulationProfile.of(.portra400)
        let p800 = FilmEmulationProfile.of(.portra800)
        XCTAssertLessThan(p160.toneG.contrast, p400.toneG.contrast)
        XCTAssertLessThan(p400.toneG.contrast, p800.toneG.contrast)
        XCTAssertLessThan(p160.mG.y, p400.mG.y)
        XCTAssertLessThan(p400.mG.y, p800.mG.y)
        // "best-in-class underexposure latitude" — 800 의 토우가 가장 많이 들린다.
        XCTAssertLessThan(p800.toneG.black, p400.toneG.black)
        XCTAssertLessThan(p400.toneG.black, p160.toneG.black)
        // 감도가 낮을수록 입자가 곱다 → 엣지 강조가 강하다.
        XCTAssertGreaterThan(p160.acutance.intensity, p800.acutance.intensity)
    }

    /// Ektar 는 네거티브 중 유일하게 고채도·고대비를 지향하고, 토우를 들지 않는다(좁은 관용도).
    func testEktarIsTheOutlierAmongNegatives() {
        let ektar = FilmEmulationProfile.of(.ektar100)
        for film in FilmEmulation.films(of: .negative) where film != .ektar100 {
            let p = FilmEmulationProfile.of(film)
            XCTAssertGreaterThan(ektar.mG.y, p.mG.y, "Ektar 채도 > \(film.rawValue)")
            XCTAssertGreaterThan(ektar.toneG.contrast, p.toneG.contrast, "Ektar 대비 > \(film.rawValue)")
        }
        XCTAssertGreaterThan(ektar.toneG.black, 0, "Ektar 는 섀도우 관용도가 좁아 토우를 들지 않습니다.")
    }

    // MARK: 슬라이드 3종 위치 (E100 < Provia < Velvia)

    func testSlideSaturationOrdering() {
        let green = solidRGB(0.14, 0.42, 0.16)
        let e100 = meanChroma(render(FilmEmulationStage.apply(to: green, emulation: .ektachromeE100, intensity: 1)))
        let provia = meanChroma(render(FilmEmulationStage.apply(to: green, emulation: .provia100F, intensity: 1)))
        let velvia = meanChroma(render(FilmEmulationStage.apply(to: green, emulation: .velvia50, intensity: 1)))
        XCTAssertGreaterThan(provia, e100 + 0.005, "Provia 채도 > E100.")
        XCTAssertGreaterThan(velvia, provia + 0.01, "Velvia 채도 > Provia.")
    }

    func testSlideContrastOrdering() {
        let dark = solid(0.16), light = solid(0.72)
        func spread(_ f: FilmEmulation) -> Double {
            let d = meanLuma(render(FilmEmulationStage.apply(to: dark, emulation: f, intensity: 1)))
            let l = meanLuma(render(FilmEmulationStage.apply(to: light, emulation: f, intensity: 1)))
            return l - d
        }
        XCTAssertGreaterThan(spread(.provia100F), spread(.ektachromeE100) + 0.005)
        XCTAssertGreaterThan(spread(.velvia50), spread(.provia100F) + 0.005)
    }

    // MARK: 네거티브 렌더 특성

    /// 네거티브는 렌더된 응답이라 슬라이드보다 톤 스프레드가 좁다(Portra 400 vs E100).
    func testPortra400RendersFlatterThanE100() {
        let dark = solid(0.16), light = solid(0.72)
        func spread(_ f: FilmEmulation) -> Double {
            let d = meanLuma(render(FilmEmulationStage.apply(to: dark, emulation: f, intensity: 1)))
            let l = meanLuma(render(FilmEmulationStage.apply(to: light, emulation: f, intensity: 1)))
            return l - d
        }
        XCTAssertLessThan(spread(.portra400), spread(.ektachromeE100) - 0.01)
    }

    /// Ektar 는 언더노출 섀도우가 블루-시안으로 기운다(반복 관측되는 고유 특성).
    func testEktarShadowsTiltBlueCyan() {
        let dark = render(FilmEmulationStage.apply(to: solid(0.14), emulation: .ektar100, intensity: 1))
        XCTAssertGreaterThan(dark.b, dark.r + 0.005, "Ektar 섀도우는 R 보다 B 가 높아야 합니다.")
    }

    /// Kodak 소비자/인물용 계열은 하이라이트가 웜(R>B)으로 기운다.
    func testKodakHighlightsTiltWarm() {
        for film in [FilmEmulation.portra800, .ultramax400, .colorPlus200] {
            let light = render(FilmEmulationStage.apply(to: solid(0.68), emulation: film, intensity: 1))
            XCTAssertGreaterThan(light.r, light.b + 0.004,
                                 "\(film.rawValue) 하이라이트는 웜이어야 합니다.")
        }
    }

    /// 같은 보급형 ISO 200 이라도 Fuji 쪽이 Kodak 보다 쿨하다.
    func testC200IsCoolerThanColorPlusInHighlights() {
        func warmth(_ f: FilmEmulation) -> Double {
            let c = render(FilmEmulationStage.apply(to: solid(0.72), emulation: f, intensity: 1))
            return c.r - c.b
        }
        XCTAssertGreaterThan(warmth(.colorPlus200), warmth(.fujicolorC200) + 0.005)
    }

    /// PRO 400H — "faithful reproduction of neutral grays over a wide exposure range".
    func testPro400HKeepsNeutralsNeutralAndIsTheSoftestFilm() {
        for v in [0.14, 0.38, 0.66] as [Float] {
            let out = render(FilmEmulationStage.apply(to: solid(v), emulation: .pro400H, intensity: 1))
            XCTAssertLessThan(meanChroma(out), 0.01,
                              "PRO 400H 는 밝기 \(v) 중립 그레이를 물들이면 안 됩니다.")
        }
        let softest = FilmEmulation.films(of: .negative)
            .min(by: { FilmEmulationProfile.of($0).toneG.contrast < FilmEmulationProfile.of($1).toneG.contrast })
        XCTAssertEqual(softest, .pro400H)
    }

    // MARK: helpers

    private func solid(_ v: Float) -> CIImage { solidRGB(v, v, v) }

    private func solidRGB(_ r: Float, _ g: Float, _ b: Float, w: Int = 16, h: Int = 16) -> CIImage {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var px = [Float](repeating: 1, count: w * h * 4)
        for i in 0..<(w * h) {
            px[i * 4] = r; px[i * 4 + 1] = g; px[i * 4 + 2] = b; px[i * 4 + 3] = 1
        }
        return CIImage(
            bitmapData: Data(bytes: px, count: px.count * MemoryLayout<Float>.size),
            bytesPerRow: w * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: w, height: h),
            format: .RGBAf,
            colorSpace: linear
        )
    }

    private func render(_ image: CIImage, w: Int = 16, h: Int = 16) -> (r: Double, g: Double, b: Double) {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        var out = [Float](repeating: 0, count: w * h * 4)
        ctx.render(image, toBitmap: &out, rowBytes: w * 4 * MemoryLayout<Float>.size,
                   bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBAf, colorSpace: linear)
        var r = 0.0, g = 0.0, b = 0.0
        let n = w * h
        for i in 0..<n { r += Double(out[i * 4]); g += Double(out[i * 4 + 1]); b += Double(out[i * 4 + 2]) }
        return (r / Double(n), g / Double(n), b / Double(n))
    }

    private func meanLuma(_ c: (r: Double, g: Double, b: Double)) -> Double {
        c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
    }

    private func meanChroma(_ c: (r: Double, g: Double, b: Double)) -> Double {
        let y = meanLuma(c)
        return sqrt(pow(c.r - y, 2) + pow(c.g - y, 2) + pow(c.b - y, 2))
    }

    private func assertEqualRGB(_ a: (r: Double, g: Double, b: Double),
                                _ b: (r: Double, g: Double, b: Double),
                                accuracy: Double) {
        XCTAssertEqual(a.r, b.r, accuracy: accuracy)
        XCTAssertEqual(a.g, b.g, accuracy: accuracy)
        XCTAssertEqual(a.b, b.b, accuracy: accuracy)
    }
}
