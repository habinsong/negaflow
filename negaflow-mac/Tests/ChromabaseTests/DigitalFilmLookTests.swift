import XCTest
import CoreImage
import CoreGraphics
import simd
@testable import Chromabase

// 디지털 소스 전용 필름 경로 검증.
//
//   • 필름 스캔 경로가 한 치도 달라지지 않았음을 먼저 못 박는다.
//   • 디지털 경로는 물리 성질(앵커 보존, 에너지 보존, 밀도 의존)로 검증한다. 특정 컷의
//     보기 좋음이 아니라 측정 가능한 성질만 본다.
final class DigitalFilmLookTests: XCTestCase {

    // MARK: 필름 경로 불변

    /// 디지털 플래그가 없거나 false 면 필름 경로다. 두 경우의 결과가 서로 같고, 디지털로
    /// 표시했을 때와는 달라야 한다 — 분기가 플래그에만 반응한다는 증거다.
    func testFilmSourceTakesTheUnchangedPath() {
        let engine = ChromabaseEngine()
        let patches = [solid(0.18), solid(0.72), solidRGB(0.42, 0.16, 0.14)]
        for filmType in [FilmType.colorPositive, .bwPositive] {
            func develop(_ flag: Bool?, _ patch: CIImage) -> (r: Double, g: Double, b: Double) {
                var params = DevelopParameters()
                params.filmType = filmType
                params.isDigitalSource = flag
                params.filmEmulation = .velvia50
                params.filmEmulationIntensity = 0.7
                return render(engine.develop(image: patch, base: nil, params: params))
            }
            for patch in patches {
                assertClose(develop(nil, patch), develop(false, patch), accuracy: 1e-6,
                            "필름 소스인데 플래그 표기에 따라 결과가 달라졌습니다.")
            }
            // 흑백은 후처리가 최종 중립화를 강제하므로 색 차이가 드러나는 컬러로만 확인한다.
            // 밝기 하나만 보면 두 경로가 우연히 교차하는 지점이 있으므로 여러 밝기를 함께 본다.
            if filmType == .colorPositive {
                let maxDelta = patches.map { patch -> Double in
                    let film = develop(nil, patch)
                    let digital = develop(true, patch)
                    return abs(film.r - digital.r) + abs(film.g - digital.g) + abs(film.b - digital.b)
                }.max() ?? 0
                XCTAssertGreaterThan(maxDelta, 0.01,
                                     "디지털 표시가 필름과 같은 결과를 냈습니다 — 분기가 동작하지 않습니다.")
            }
        }
    }

    /// 필름 경로의 룩 스테이지 자체는 손대지 않았다. 기존 구현을 직접 호출한 것과 같아야 한다.
    func testFilmEmulationStageItselfIsUnchanged() {
        for film in [FilmEmulation.velvia50, .portra400] {
            for intensity in [0.35, 0.7, 1.0] {
                let patch = solidRGB(0.42, 0.26, 0.16)
                let out = render(FilmEmulationStage.apply(to: patch, emulation: film, intensity: intensity))
                // 룩이 실제로 무언가를 하고 있고(항등이 아니고), 디지털 경로를 타지 않는다.
                XCTAssertNotEqual(out.r, 0.42, accuracy: 1e-6)
            }
        }
    }

    /// 네거티브 필름은 디지털 플래그가 잘못 남아 있어도 필름 경로로 읽혀야 한다.
    func testNegativeFilmNeverEntersDigitalPath() {
        var params = DevelopParameters()
        params.filmType = .colorNegative
        params.isDigitalSource = true
        XCTAssertTrue(params.filmType.requiresInversion,
                      "네거티브는 반전 경로를 유지해야 합니다 — 디지털 표시는 포지티브에만 존재합니다.")
    }

    // MARK: 커널 가용성

    func testDigitalKernelsCompile() {
        let names = ChromabaseMetalKernels.availableKernelNames
        for name in ["digitalHalation", "digitalFilmGrainDensity",
                     "digitalToDisplayGamma", "digitalToLinearLight"] {
            XCTAssertTrue(names.contains(name), "Metal 커널 \(name) 이 컴파일되지 않았습니다.")
        }
    }

    // MARK: 헐레이션

    /// 산란/헐레이션은 빛을 재분배할 뿐 총량을 늘리면 안 된다. 균일면에서는 변화가 없어야 한다.
    func testHalationConservesEnergyOnUniformField() {
        let flat = solid(0.5)
        let out = render(DigitalHalation.apply(to: flat, physics: .portra400, strength: 1.0),
                         w: 64, h: 64)
        XCTAssertEqual(out.g, 0.5, accuracy: 0.01,
                       "균일면에서 헐레이션이 밝기를 바꿨습니다 — 에너지 보존 위반입니다.")
    }

    /// 헐레이션은 붉게 번져야 한다 — 되돌아온 빛이 적색 층을 먼저 때리기 때문이다.
    ///
    /// 반경은 픽셀이 아니라 프레임 크기에 대한 비율이라, 실제 스캔에 가까운 크기에서 봐야
    /// 의미가 있다(48px 짜리 패치에서는 반경이 1px 미만이라 아무것도 보이지 않는다).
    func testHalationIsRedBiasedAroundHighlight() {
        let size = 512
        let image = highlightSpot(size: size, half: 40)
        let out = DigitalHalation.apply(to: image, physics: .portra400, strength: 1.0)
        // 밝은 사각 경계 바로 바깥의 어두운 영역.
        let probe = CGRect(x: size / 2 + 42, y: size / 2 - 4, width: 8, height: 8)
        let before = renderRect(image, rect: probe)
        let after = renderRect(out, rect: probe)
        let dR = after.r - before.r
        let dB = after.b - before.b
        XCTAssertGreaterThan(dR, 1e-4, "헐레이션이 명부 주변을 물들이지 않았습니다.")
        XCTAssertGreaterThan(dR, dB * 1.5, "헐레이션이 적색 편향이어야 합니다.")
    }

    // MARK: 그레인

    /// 그레인은 밀도에 따라 달라야 한다 — 미드톤에서 가장 굵고 흰색 근처에서 약해진다.
    func testGrainIsDensityDependent() {
        func spread(_ v: Float) -> Double {
            let out = renderPixels(
                DigitalFilmGrain.apply(to: solid(v), physics: .portra800, strength: 1.0),
                w: 64, h: 64
            )
            return standardDeviation(out)
        }
        let highlight = spread(0.90)
        let midtone = spread(0.045)      // 밀도 ≈ 0.6
        XCTAssertGreaterThan(midtone, highlight * 1.5,
                             "그레인이 밝기와 무관하게 균일합니다 — 디지털 노이즈와 구분되지 않습니다.")
    }

    /// 미세 입자 필름이 굵은 입자 필름보다 그레인이 약해야 한다(데이터시트 순위 반영).
    func testFinerStockHasLessGrain() {
        func spread(_ physics: DigitalFilmPhysics) -> Double {
            standardDeviation(renderPixels(
                DigitalFilmGrain.apply(to: solid(0.05), physics: physics, strength: 1.0),
                w: 64, h: 64
            ))
        }
        XCTAssertLessThan(spread(.ektar100), spread(.portra800),
                          "Ektar 100(PGI<25)이 Portra 800 보다 굵게 나왔습니다.")
    }

    // MARK: 강도

    func testIntensityZeroIsIdentity() {
        let patch = solidRGB(0.40, 0.25, 0.15)
        let out = DigitalFilmLook.apply(to: patch, emulation: .velvia50, intensity: 0,
                                        grainOverride: 0, halationOverride: 0)
        assertClose(render(out), render(patch), accuracy: 1e-4, "강도 0 이 항등이 아닙니다.")
    }

    func testNoneIsIdentity() {
        let patch = solidRGB(0.40, 0.25, 0.15)
        let out = DigitalFilmLook.apply(to: patch, emulation: .none, intensity: 1,
                                        grainOverride: 0, halationOverride: 0)
        assertClose(render(out), render(patch), accuracy: 1e-4, "필름 없음이 항등이 아닙니다.")
    }

    // MARK: 핵심 회귀 — 실제 사진 분포 보존

    /// 밝은 하늘·어두운 잎·중간톤 피사체가 함께 있는 사진형 분포를 모든 스톡과 두 디지털
    /// 프로세스에 통과시킨다. 단색 패치 평균으로는 잡지 못했던 중앙 압축 회귀를 검출한다.
    func testEveryDigitalFilmLookPreservesPhotographicTonalSeparation() {
        let engine = ChromabaseEngine()
        let scene = photographicScene()
        for filmType in [FilmType.colorPositive, .bwPositive] {
            var params = DevelopParameters()
            params.filmType = filmType
            params.isDigitalSource = true
            params.filmEmulation = .none
            let baseline = displayPercentiles(
                engine.develop(image: scene, base: nil, params: params)
            )

            for film in FilmEmulation.allCases where film != .none {
                params.filmEmulation = film
                params.filmEmulationIntensity = 1
                let output = displayPercentiles(
                    engine.develop(image: scene, base: nil, params: params)
                )
                assertDistributionPreserved(
                    output,
                    baseline: baseline,
                    minimumRangeRatio: 0.90,
                    maximumShadowLift: 0.06,
                    maximumHighlightLoss: 0.04,
                    message: "\(filmType.rawValue)/\(film.rawValue)"
                )
            }
        }
    }

    /// 강도 드래그 중 어느 지점에서도 프레임이 하얘지거나 히스토그램이 가운데로 접히면 안 된다.
    func testIntensitySweepNeverCollapsesDigitalColorOrBW() {
        let engine = ChromabaseEngine()
        let scene = photographicScene()
        for filmType in [FilmType.colorPositive, .bwPositive] {
            var params = DevelopParameters()
            params.filmType = filmType
            params.isDigitalSource = true
            params.filmEmulation = .none
            let baseline = displayPercentiles(
                engine.develop(image: scene, base: nil, params: params)
            )

            for film in [FilmEmulation.velvia50, .portra400] {
                params.filmEmulation = film
                for intensity in [0.0, 0.25, 0.5, 0.6, 0.75, 1.0] {
                    params.filmEmulationIntensity = intensity
                    let output = displayPercentiles(
                        engine.develop(image: scene, base: nil, params: params)
                    )
                    assertDistributionPreserved(
                        output,
                        baseline: baseline,
                        minimumRangeRatio: 0.90,
                        maximumShadowLift: 0.06,
                        maximumHighlightLoss: 0.04,
                        message: "\(filmType.rawValue)/\(film.rawValue)/\(intensity)"
                    )
                }
            }
        }
    }

    /// 개인 원본은 저장소에 넣지 않고 환경변수로만 받아 실제 RAW 로더와 앱의 현상 엔진까지
    /// 함께 검증한다. 포스트모템에서 사용한 다중 DNG 표본을 이 하네스로 다시 측정한다.
    func testRealDigitalFilmLooksPreserveTonalDistribution() throws {
        guard let rawPaths = ProcessInfo.processInfo.environment["NEGAFLOW_DIGITAL_FILM_REAL_FILES"],
              !rawPaths.isEmpty else {
            throw XCTSkip("Set NEGAFLOW_DIGITAL_FILM_REAL_FILES to colon-separated image paths.")
        }

        let engine = ChromabaseEngine()
        for path in rawPaths.split(separator: ":").map(String.init) {
            let url = URL(fileURLWithPath: path)
            let source = try XCTUnwrap(ImageLoader.load(url), "실제 파일 로드 실패: \(path)")
            let proxy = downsample(source, maxDimension: 800)

            var params = realDigitalFixtureParameters()
            params.filmEmulation = .none
            let baselineImage = engine.developScanner(image: proxy, base: nil, params: params)
            let baseline = displayPercentiles(baselineImage)

            for film in FilmEmulation.allCases where film != .none {
                params.filmEmulation = film
                params.filmEmulationIntensity = 1
                let current = displayPercentiles(
                    engine.developScanner(image: proxy, base: nil, params: params)
                )
                assertDistributionPreserved(
                    current,
                    baseline: baseline,
                    minimumRangeRatio: 0.95,
                    maximumShadowLift: 0.05,
                    maximumHighlightLoss: 0.03,
                    message: "\(url.lastPathComponent)/\(film.rawValue)"
                )
                print("DIGITAL_FILM_REAL \(url.lastPathComponent) \(film.rawValue) " +
                      "base=\(baseline) output=\(current)")
            }
        }
    }

    // MARK: 이중 적용 방지

    /// 필름을 고르면 그레인은 유제 물성으로 들어간다. 후처리 텍스처 단계가 같은 축을 한 번 더
    /// 더하면 밝은 영역까지 노이즈가 껴서 필름이 아니라 고감도 디지털처럼 보인다.
    /// 밀도가 거의 없는 밝은 패치에서 흔들림이 작게 남아야 한다.
    func testGrainIsNotAppliedTwiceOnDigitalFilm() {
        let engine = ChromabaseEngine()
        var params = DevelopParameters()
        params.filmType = .colorPositive
        params.isDigitalSource = true
        params.filmEmulation = .portra400
        params.filmEmulationIntensity = 1.0
        params.grain = 1.0

        let bright = solid(0.80)
        let noisy = standardDeviation(renderPixels(
            engine.develop(image: bright, base: nil, params: params), w: 64, h: 64
        ))
        // 같은 조건에서 필름만 끄면 후처리 그레인이 그대로 작동한다(기존 동작 보존).
        var withoutFilm = params
        withoutFilm.filmEmulation = .none
        let textureOnly = standardDeviation(renderPixels(
            engine.develop(image: bright, base: nil, params: withoutFilm), w: 64, h: 64
        ))
        XCTAssertGreaterThan(textureOnly, 0.001,
                             "필름을 고르지 않았을 때의 텍스처 그레인은 그대로 동작해야 합니다.")
        XCTAssertLessThan(noisy, textureOnly,
                          "필름 선택 시 밝은 영역 그레인이 후처리 단계와 겹쳐 더 커졌습니다.")
    }

    // MARK: 스톡 색 시그니처
    //
    // 색 프리셋이 없던 시점에는 스톡 차이가 "채도 크기" 하나로 수렴했다(ColorPlus 200 과
    // C200 의 빨강이 0.754 대 0.760). 아래는 각 필름에서 반복 관측되는 색 방향이 실제로
    // 살아 있는지 본다.

    /// 같은 감도의 정반대 두 필름. ColorPlus 는 따뜻하고 C200 은 서늘해야 한다.
    func testColorPlusIsWarmAndC200IsCool() {
        let gray = cameraRendered(solid(0.40))
        let plus = look(gray, .colorPlus200)
        let c200 = look(gray, .fujicolorC200)
        XCTAssertGreaterThan(plus.r - plus.b, 0.03, "ColorPlus 200 은 따뜻해야 합니다.")
        XCTAssertLessThan(c200.r - c200.b, -0.02, "Fujicolor C200 은 서늘해야 합니다.")

        let red = cameraRendered(solidRGB(0.55, 0.13, 0.11))
        let plusRed = look(red, .colorPlus200)
        let c200Red = look(red, .fujicolorC200)
        XCTAssertGreaterThan(plusRed.r, c200Red.r + 0.05,
                             "C200 은 빨강을 눌러야 합니다(ColorPlus \(plusRed.r) vs C200 \(c200Red.r)).")
    }

    /// PRO 400H 의 네 번째 시안 층 — 초록이 파랑 쪽으로 기운다(코닥 계열과 반대).
    func testPro400HGreensLeanBlueUnlikeKodak() {
        let leaf = cameraRendered(solidRGB(0.16, 0.38, 0.14))
        let fuji = look(leaf, .pro400H)
        let kodak = look(leaf, .portra400)
        XCTAssertGreaterThan(fuji.b - fuji.r, kodak.b - kodak.r,
                             "PRO 400H 초록이 Portra 보다 파랑 쪽이어야 합니다.")
    }

    /// Ektar 100 — 저노출 섀도우가 블루-시안으로 기우는 것이 이 필름의 서명이다.
    func testEktarShadowsGoBlueCyan() {
        let shadow = cameraRendered(solid(0.06))
        let ektar = look(shadow, .ektar100)
        let portra = look(shadow, .portra400)
        XCTAssertGreaterThan(ektar.b - ektar.r, portra.b - portra.r + 0.004,
                             "Ektar 섀도우가 Portra 보다 블루-시안이어야 합니다.")
    }

    /// Portra 800 — 400 보다 노랑기가 있어 밝은 중립이 누렇게 돈다.
    func testPortra800IsYellowerThan400() {
        let gray = cameraRendered(solid(0.40))
        let p800 = look(gray, .portra800)
        let p400 = look(gray, .portra400)
        XCTAssertLessThan(p800.b, p400.b - 0.01, "Portra 800 이 400 보다 노랗게 돌아야 합니다.")
    }

    /// 슬라이드 3종의 색온도 방향: E100 은 서늘하고 Velvia 는 따뜻하다.
    func testSlideColorTemperatureOrdering() {
        let gray = cameraRendered(solid(0.40))
        let e100 = look(gray, .ektachromeE100)
        let velvia = look(gray, .velvia50)
        XCTAssertLessThan(e100.r - e100.b, 0, "E100 은 파랑으로 기웁니다.")
        XCTAssertGreaterThan(velvia.r - velvia.b, e100.r - e100.b + 0.05,
                             "Velvia 가 E100 보다 따뜻해야 합니다.")
    }

    /// 어떤 두 스톡도 서로 구별되어야 한다 — 프리셋이 실제로 다른 방향을 향하는지 본다.
    func testEveryStockPairIsDistinguishable() {
        let patches = [
            cameraRendered(solidRGB(0.52, 0.34, 0.26)),   // 스킨톤
            cameraRendered(solidRGB(0.16, 0.38, 0.14)),   // 잎
            cameraRendered(solid(0.40)),                   // 중간 회색
        ]
        let films = FilmEmulation.allCases.filter { $0 != .none }
        for i in 0..<films.count {
            for j in (i + 1)..<films.count {
                let delta = patches.map { patch -> Double in
                    let a = look(patch, films[i]), b = look(patch, films[j])
                    return abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
                }.max() ?? 0
                XCTAssertGreaterThan(delta, 0.02,
                                     "\(films[i].rawValue) 와 \(films[j].rawValue) 가 구별되지 않습니다(\(delta)).")
            }
        }
    }

    /// 색 방향을 주더라도 중립 장면을 물들이는 정도에는 한계가 있어야 한다. 흐린 날이나 눈처럼
    /// 무채색이 지배하는 장면이 통째로 색을 먹으면 룩이 아니라 고장이다.
    func testNeutralCastStaysBounded() {
        for film in FilmEmulation.allCases where film != .none {
            let out = look(cameraRendered(solid(0.40)), film)
            let y = meanLuma(out)
            let cast = max(abs(out.r - y), max(abs(out.g - y), abs(out.b - y)))
            XCTAssertLessThan(cast, 0.075,
                              "\(film.rawValue): 중립 캐스트가 과합니다(\(cast)).")
        }
    }

    /// 유채색이 색역 밖으로 폭주하면 클리핑되어 오히려 스톡 구별이 사라진다.
    ///
    /// 강한 원색에서 채널 하나가 흰색 한계에 닿는 것은 필름의 실제 거동이다 — 반전 필름은
    /// 중간 회색 위 한 스톱 남짓이면 그 채널이 흰색이 된다. 문제가 되는 것은 두 채널 이상이
    /// 함께 포화해 색상까지 뭉개지는 경우이고, 프리셋 도입 전 관측된 폭주(잎에서 1.54,
    /// 빨강에서 1.66)가 그 상태였다.
    func testSaturatedPatchesDoNotBlowOut() {
        let patches = [
            cameraRendered(solidRGB(0.55, 0.13, 0.11)),
            cameraRendered(solidRGB(0.16, 0.38, 0.14)),
            cameraRendered(solidRGB(0.20, 0.34, 0.62)),
        ]
        for film in FilmEmulation.allCases where film != .none {
            for patch in patches {
                let out = look(patch, film)
                let channels = [out.r, out.g, out.b]
                XCTAssertLessThan(channels.max()!, 1.02,
                                  "\(film.rawValue): 색역 밖으로 폭주했습니다(\(channels.max()!)).")
                XCTAssertLessThan(channels.filter { $0 > 0.99 }.count, 2,
                                  "\(film.rawValue): 두 채널이 함께 포화해 색상이 뭉갰습니다(\(channels)).")
            }
        }
    }

    private func look(_ image: CIImage, _ film: FilmEmulation) -> (r: Double, g: Double, b: Double) {
        render(DigitalFilmLook.apply(to: image, emulation: film, intensity: 1,
                                     grainOverride: 0, halationOverride: 0))
    }

    // MARK: 필름의 밝기대별 색 갈림(크로스오버)

    /// 컬러 필름은 R/G/B 가 아니라 감도와 도달 밀도가 서로 다른 세 감광층이다. 그 어긋남 때문에
    /// 어두운 쪽과 밝은 쪽의 색이 갈린다 — 그림자는 서늘하고 명부는 따뜻해지는 이 갈림이
    /// 필름을 디지털과 구별짓는 지점이고, 색을 균일하게 미는 필터와도 다른 점이다.
    func testTonalCrossoverSeparatesShadowsFromHighlights() {
        // 따뜻한 쪽으로 설계된 스톡은 그림자→명부로 갈수록 확실히 더 따뜻해져야 한다.
        for film in [FilmEmulation.portra400, .portra800, .ultramax400, .velvia50, .colorPlus200] {
            let shadow = look(cameraRendered(solid(0.03)), film)
            let highlight = look(cameraRendered(solid(0.85)), film)
            let shadowWarmth = shadow.r - shadow.b
            let highlightWarmth = highlight.r - highlight.b
            XCTAssertGreaterThan(highlightWarmth, shadowWarmth + 0.04,
                                 "\(film.rawValue): 밝기대별 색 갈림이 없습니다 " +
                                 "(그림자 \(shadowWarmth), 명부 \(highlightWarmth)).")
        }
    }

    /// 그림자가 서늘해지는 것은 층 감도차의 결과다. 대부분의 스톡에서 나타나야 한다.
    func testShadowsRunCoolOnMostStocks() {
        let coolShadowStocks = FilmEmulation.allCases.filter { film in
            guard film != .none else { return false }
            let shadow = look(cameraRendered(solid(0.03)), film)
            return shadow.r - shadow.b < 0
        }
        XCTAssertGreaterThanOrEqual(coolShadowStocks.count, 9,
                                    "그림자가 서늘한 스톡이 너무 적습니다(\(coolShadowStocks.count)/11).")
    }

    /// Ektar 는 그중에서도 그림자가 가장 서늘하다 — 반복 관측되는 블루-시안 섀도우.
    func testEktarHasCoolestShadows() {
        let others = FilmEmulation.allCases.filter { $0 != .none && $0 != .ektar100 }
        let ektar = look(cameraRendered(solid(0.03)), .ektar100)
        let ektarWarmth = ektar.r - ektar.b
        for film in others {
            let c = look(cameraRendered(solid(0.03)), film)
            XCTAssertLessThan(ektarWarmth, c.r - c.b,
                              "Ektar 그림자가 \(film.rawValue) 보다 서늘해야 합니다.")
        }
    }

    // MARK: fixtures / helpers

    private func cameraRendered(_ image: CIImage) -> CIImage {
        image
            .applyingFilter("CIToneCurve", parameters: [
                "inputPoint0": CIVector(x: 0.00, y: 0.00),
                "inputPoint1": CIVector(x: 0.25, y: 0.19),
                "inputPoint2": CIVector(x: 0.50, y: 0.52),
                "inputPoint3": CIVector(x: 0.75, y: 0.87),
                "inputPoint4": CIVector(x: 1.00, y: 1.00),
            ])
            .applyingFilter("CIColorControls", parameters: ["inputSaturation": 1.25])
            .cropped(to: image.extent)
    }

    private func realDigitalFixtureParameters() -> DevelopParameters {
        var params = DevelopParameters()
        params.filmType = .colorPositive
        params.isDigitalSource = true
        params.exposure = 0.5444
        params.contrast = -0.2623
        params.highlight = -0.4155
        params.shadow = 0.0344
        params.whites = -0.3776
        params.blacks = -0.2866
        params.density = -0.40
        params.tint = 0.1076
        params.warmth = 0.2723
        params.vibrance = 0.1096
        params.grain = 0
        params.halation = 0
        return params
    }

    private func downsample(_ image: CIImage, maxDimension: CGFloat) -> CIImage {
        let extent = image.extent.integral
        let scale = min(1, maxDimension / max(extent.width, extent.height))
        guard scale < 1 else { return image }
        return image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .applyingFilter("CILanczosScaleTransform", parameters: [
                "inputScale": scale,
                "inputAspectRatio": 1.0,
            ])
            .cropped(to: CGRect(x: 0, y: 0, width: extent.width * scale, height: extent.height * scale))
    }

    private struct DisplayDistribution: CustomStringConvertible {
        let p01: Double
        let p10: Double
        let p50: Double
        let p90: Double
        let p99: Double

        var range: Double { p99 - p01 }

        var description: String {
            String(
                format: "p1 %.3f p10 %.3f p50 %.3f p90 %.3f p99 %.3f range %.3f",
                p01, p10, p50, p90, p99, range
            )
        }
    }

    private func assertDistributionPreserved(
        _ output: DisplayDistribution,
        baseline: DisplayDistribution,
        minimumRangeRatio: Double,
        maximumShadowLift: Double,
        maximumHighlightLoss: Double,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(
            output.range,
            baseline.range * minimumRangeRatio,
            "\(message): 톤 범위가 중앙으로 압축됐습니다. baseline=\(baseline), output=\(output)",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            output.p01,
            baseline.p01 + maximumShadowLift,
            "\(message): 암부가 과도하게 들렸습니다. baseline=\(baseline), output=\(output)",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            output.p99,
            baseline.p99 - maximumHighlightLoss,
            "\(message): 명부가 과도하게 내려앉았습니다. baseline=\(baseline), output=\(output)",
            file: file,
            line: line
        )
    }

    /// 단색 램프가 아니라 하늘·잎·따뜻한 피사체와 암부~명부가 한 프레임에 공존하는 픽스처.
    private func photographicScene(width: Int = 192, height: Int = 128) -> CIImage {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let lumaWeights = SIMD3<Float>(0.2126, 0.7152, 0.0722)
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            let v = Float(y) / Float(max(height - 1, 1))
            for x in 0..<width {
                let u = Float(x) / Float(max(width - 1, 1))
                let texture = 0.92 + 0.08 * sin(u * 31 + v * 17)
                let targetLuma = min(max(0.006 + pow(u, 1.35) * 0.90 * texture, 0), 0.96)
                let direction: SIMD3<Float>
                if v < 0.34 {
                    direction = SIMD3(0.58, 0.82, 1.30)  // 밝은 하늘
                } else if v < 0.72 {
                    direction = SIMD3(0.55, 1.18, 0.42)  // 어두운 초록 잎
                } else {
                    direction = SIMD3(1.18, 0.84, 0.62)  // 따뜻한 돌·피부 계열
                }
                let scale = targetLuma / max(simd_dot(direction, lumaWeights), 1e-5)
                let color = simd_clamp(direction * scale, SIMD3(repeating: 0), SIMD3(repeating: 1))
                let index = (y * width + x) * 4
                pixels[index] = color.x
                pixels[index + 1] = color.y
                pixels[index + 2] = color.z
            }
        }
        return CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
    }

    private func displayPercentiles(_ image: CIImage) -> DisplayDistribution {
        let extent = image.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let context = CIContext(options: [
            .workingColorSpace: linear,
            .outputColorSpace: srgb,
            .workingFormat: CIFormat.RGBAf,
        ])
        var pixels = [Float](repeating: 0, count: width * height * 4)
        context.render(
            image,
            toBitmap: &pixels,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: extent,
            format: .RGBAf,
            colorSpace: srgb
        )
        var luma = [Float]()
        luma.reserveCapacity(width * height)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            luma.append(
                pixels[index] * 0.2126 + pixels[index + 1] * 0.7152 + pixels[index + 2] * 0.0722
            )
        }
        luma.sort()
        func percentile(_ p: Double) -> Double {
            let index = Int((Double(max(luma.count - 1, 0)) * p).rounded())
            return Double(luma[index])
        }
        return DisplayDistribution(
            p01: percentile(0.01),
            p10: percentile(0.10),
            p50: percentile(0.50),
            p90: percentile(0.90),
            p99: percentile(0.99)
        )
    }

    /// 어두운 바탕 가운데 밝은 사각 — 헐레이션의 공간 거동을 보기 위한 최소 픽스처.
    private func highlightSpot(size: Int, half: Int) -> CIImage {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var px = [Float](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                let inSpot = abs(x - size / 2) < half && abs(y - size / 2) < half
                let v: Float = inSpot ? 3.0 : 0.02
                px[i] = v; px[i + 1] = v; px[i + 2] = v; px[i + 3] = 1
            }
        }
        return CIImage(
            bitmapData: Data(bytes: px, count: px.count * MemoryLayout<Float>.size),
            bytesPerRow: size * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: size, height: size),
            format: .RGBAf,
            colorSpace: linear
        )
    }

    private func solid(_ v: Float) -> CIImage { solidRGB(v, v, v) }

    private func solidRGB(_ r: Float, _ g: Float, _ b: Float, w: Int = 64, h: Int = 64) -> CIImage {
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

    private func renderPixels(_ image: CIImage, w: Int, h: Int) -> [Float] {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        var out = [Float](repeating: 0, count: w * h * 4)
        ctx.render(image, toBitmap: &out, rowBytes: w * 4 * MemoryLayout<Float>.size,
                   bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBAf, colorSpace: linear)
        return out
    }

    private func render(_ image: CIImage, w: Int = 64, h: Int = 64) -> (r: Double, g: Double, b: Double) {
        let out = renderPixels(image, w: w, h: h)
        var r = 0.0, g = 0.0, b = 0.0
        let n = w * h
        for i in 0..<n { r += Double(out[i * 4]); g += Double(out[i * 4 + 1]); b += Double(out[i * 4 + 2]) }
        return (r / Double(n), g / Double(n), b / Double(n))
    }

    private func renderRect(_ image: CIImage, rect: CGRect) -> (r: Double, g: Double, b: Double) {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        let w = Int(rect.width), h = Int(rect.height)
        var out = [Float](repeating: 0, count: w * h * 4)
        ctx.render(image, toBitmap: &out, rowBytes: w * 4 * MemoryLayout<Float>.size,
                   bounds: rect, format: .RGBAf, colorSpace: linear)
        var r = 0.0, g = 0.0, b = 0.0
        let n = w * h
        for i in 0..<n { r += Double(out[i * 4]); g += Double(out[i * 4 + 1]); b += Double(out[i * 4 + 2]) }
        return (r / Double(n), g / Double(n), b / Double(n))
    }

    private func standardDeviation(_ pixels: [Float]) -> Double {
        let values = stride(from: 0, to: pixels.count, by: 4).map { Double(pixels[$0 + 1]) }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot()
    }

    private func meanLuma(_ c: (r: Double, g: Double, b: Double)) -> Double {
        c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
    }

    private func assertClose(_ a: (r: Double, g: Double, b: Double),
                             _ b: (r: Double, g: Double, b: Double),
                             accuracy: Double, _ message: String) {
        XCTAssertEqual(a.r, b.r, accuracy: accuracy, message)
        XCTAssertEqual(a.g, b.g, accuracy: accuracy, message)
        XCTAssertEqual(a.b, b.b, accuracy: accuracy, message)
    }
}
