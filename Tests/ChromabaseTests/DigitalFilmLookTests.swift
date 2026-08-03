import XCTest
import CoreImage
import CoreGraphics
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
        for name in ["digitalSceneReconstruct", "digitalFilmDensity", "digitalInterImage",
                     "digitalPrintPaper", "digitalReversalTransmit", "digitalHalation",
                     "digitalFilmColor", "digitalFilmGrainDensity"] {
            XCTAssertTrue(names.contains(name), "Metal 커널 \(name) 이 컴파일되지 않았습니다.")
        }
    }

    // MARK: 노출 재구성

    /// 중간 회색은 재구성을 지나도 그대로여야 한다 — 노출 앵커가 흔들리면 전 체인이 밀린다.
    func testSceneReconstructKeepsMidGray() {
        let out = render(DigitalSceneReconstruct.apply(to: solid(0.18)))
        XCTAssertEqual(out.g, 0.18, accuracy: 0.002)
    }

    /// 명부는 확장되고 곡선은 단조 증가여야 한다(반전 없이 계조 순서 보존).
    func testSceneReconstructExpandsHighlightsMonotonically() {
        let values: [Float] = [0.05, 0.18, 0.35, 0.55, 0.70, 0.85, 0.95]
        var previous = -1.0
        var gains: [Double] = []
        for v in values {
            let out = render(DigitalSceneReconstruct.apply(to: solid(v))).g
            XCTAssertGreaterThan(out, previous, "재구성 곡선이 단조 증가가 아닙니다(v=\(v)).")
            previous = out
            gains.append(out / Double(v))
        }
        XCTAssertGreaterThan(gains.last!, gains.first! * 3,
                             "명부가 암부보다 크게 확장되어야 헤드룸이 생깁니다.")
    }

    // MARK: 가상 현상

    /// 노출 → 밀도 → (인화 또는 투과) 전 구간에서 중간 회색이 보존되어야 한다.
    func testDevelopChainPreservesMidGrayForEveryStock() {
        for film in FilmEmulation.allCases where film != .none {
            guard let physics = DigitalFilmPhysics.of(film) else { continue }
            let out = render(DigitalFilmDevelop.apply(to: solid(0.18), physics: physics))
            XCTAssertEqual(out.g, 0.18, accuracy: 0.012,
                           "\(film.rawValue): 가상 현상이 중간 회색을 옮겼습니다.")
        }
    }

    /// 층간 억제는 무채색을 건드리지 않고 유채색만 벌린다 — DIR 커플러가 채도를 만드는 방식.
    func testInterImageKeepsNeutralAndSeparatesColor() {
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "digitalInterImage") else {
            return XCTFail("digitalInterImage 커널 없음")
        }
        let k = CIVector(x: 0.2, y: 0.3, z: 0.15, w: 0)
        func run(_ image: CIImage) -> (r: Double, g: Double, b: Double) {
            render(kernel.apply(extent: image.extent, arguments: [image, k])!.cropped(to: image.extent))
        }
        // 무채색(같은 밀도) — 정확히 보존되어야 한다.
        let neutral = run(solidRGB(0.42, 0.42, 0.42))
        XCTAssertEqual(neutral.r, 0.42, accuracy: 1e-3)
        XCTAssertEqual(neutral.g, 0.42, accuracy: 1e-3)
        XCTAssertEqual(neutral.b, 0.42, accuracy: 1e-3)

        // 유채색 — 채널 간격이 벌어져야 한다.
        let before = solidRGB(0.50, 0.40, 0.30)
        let after = run(before)
        let spreadBefore = 0.50 - 0.30
        let spreadAfter = after.r - after.b
        XCTAssertGreaterThan(spreadAfter, spreadBefore + 0.01,
                             "층간 억제가 색 대비를 벌리지 못했습니다.")
    }

    /// 네거티브는 인화지를 거쳐 명부가 눕고, 반전은 더 빨리 날아간다 — 관용도 차이가
    /// 곡선에서 자연히 나와야 한다.
    func testNegativeHoldsHighlightsLongerThanReversal() {
        let negative = DigitalFilmPhysics.portra400
        let reversal = DigitalFilmPhysics.velvia50
        func output(_ physics: DigitalFilmPhysics, stops: Double) -> Double {
            let e = Float(0.18 * pow(2.0, stops))
            return render(DigitalFilmDevelop.apply(to: solid(e), physics: physics)).g
        }
        // +2 스톱에서 반전이 네거티브보다 확실히 더 밝게(= 먼저 포화) 나와야 한다.
        let negAt2 = output(negative, stops: 2)
        let revAt2 = output(reversal, stops: 2)
        XCTAssertGreaterThan(revAt2, negAt2 + 0.05,
                             "반전이 네거티브보다 명부를 오래 붙들고 있습니다 — 관용도가 뒤집혔습니다.")
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

    // MARK: 핵심 회귀 — 명부 계조

    /// 진단에서 확인한 붕괴(카메라 렌더 입력 + 색 LUT 에서 명부 스텝 0.0031)가 해소되어야 한다.
    ///
    /// 기준은 "LUT 보다 큰가" 가 아니다. 연조 네거티브에서는 LUT 가 명부를 거의 건드리지 않아
    /// 스텝이 크게 남는데, 그건 롤오프를 안 한 것이지 잘한 것이 아니다. 필름은 명부를 압축
    /// **하면서도** 계조를 남긴다 — 그래서 절대량과 미드톤 대비 비율로 본다.
    func testDigitalPathKeepsHighlightSteps() {
        let steps: [Float] = [0.55, 0.65, 0.75, 0.85, 0.95]
        for film in FilmEmulation.allCases where film != .none {
            func gaps(_ transform: (CIImage) -> CIImage) -> [Double] {
                let ys = steps.map { meanLuma(render(transform(cameraRendered(solid($0))))) }
                return zip(ys.dropFirst(), ys).map { $0 - $1 }
            }
            let digital = gaps {
                DigitalFilmLook.apply(to: $0, emulation: film, intensity: 1,
                                      grainOverride: 0, halationOverride: 0)
            }
            let top = digital.last!
            let mid = digital.first!
            // 반전 필름은 중간 회색 위 한 스톱 남짓이면 흰색이라, 명부를 네거티브만큼 담지
            // 못하는 것이 물성이다. 인화지를 한 번 더 거치는 네거티브에는 더 높은 선을 요구한다.
            let isReversal = DigitalFilmPhysics.of(film)?.isReversal ?? false
            let floor = isReversal ? 0.0035 : 0.0065
            XCTAssertGreaterThan(top, floor,
                                 "\(film.rawValue): 최명부 스텝이 붕괴 상태입니다(\(top)).")
            XCTAssertGreaterThan(top / mid, 0.05,
                                 "\(film.rawValue): 명부가 미드톤 대비 과도하게 뭉갰습니다 " +
                                 "(mid \(mid), top \(top)).")
        }
    }

    /// 같은 입력에서 고대비 반전 필름은 색 LUT 보다 명부를 더 남겨야 한다 — 진단에서 붕괴가
    /// 가장 심했던 조합이다. 배수를 크게 요구하지는 않는다. LUT 쪽 값은 명부를 손대지 않아
    /// 남은 것이라 비교의 기준점일 뿐, 넘어야 할 목표가 아니기 때문이다.
    func testDigitalPathBeatsLUTWhereCollapseWasWorst() {
        let steps: [Float] = [0.85, 0.95]
        func topGap(_ transform: (CIImage) -> CIImage) -> Double {
            let ys = steps.map { meanLuma(render(transform(cameraRendered(solid($0))))) }
            return ys[1] - ys[0]
        }
        let lut = topGap { FilmEmulationStage.apply(to: $0, emulation: .velvia50, intensity: 1) }
        let digital = topGap {
            DigitalFilmLook.apply(to: $0, emulation: .velvia50, intensity: 1,
                                  grainOverride: 0, halationOverride: 0)
        }
        XCTAssertGreaterThan(digital, lut * 1.2,
                             "Velvia 명부 계조가 색 LUT 대비 개선되지 않았습니다 " +
                             "(LUT \(lut) vs 디지털 \(digital)).")
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
        XCTAssertGreaterThan(plusRed.r, c200Red.r * 1.25,
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
            XCTAssertGreaterThan(highlightWarmth, shadowWarmth + 0.05,
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

    // MARK: 필름다운 톤 레인지

    /// 필름을 거친 이미지에는 진짜 검정도 순백도 없다. 베이스와 카브리가 바닥을 만들고
    /// 매체의 반사·투과 한계가 천장을 만든다. 양 끝이 0 과 1 에 붙으면 디지털이지 필름이 아니다.
    func testNoTrueBlackOrTrueWhite() {
        for film in FilmEmulation.allCases where film != .none {
            let black = meanLuma(look(cameraRendered(solid(0.0)), film))
            let white = meanLuma(look(cameraRendered(solid(0.98)), film))
            XCTAssertGreaterThan(black, 0.003,
                                 "\(film.rawValue): 검정이 바닥에 붙었습니다(\(black)).")
            XCTAssertLessThan(black, 0.055,
                              "\(film.rawValue): 검정이 지나치게 떠서 뿌옇습니다(\(black)).")
            XCTAssertLessThan(white, 0.93,
                              "\(film.rawValue): 명부가 순백까지 갔습니다(\(white)).")
            XCTAssertGreaterThan(white, 0.55,
                                 "\(film.rawValue): 명부가 회색에 머물러 흐립니다(\(white)).")
        }
    }

    /// 네거티브는 인화지를 한 번 더 거치므로 반전보다 검정이 덜 떨어진다.
    func testNegativeBlacksSitHigherThanReversal() {
        let negative = meanLuma(look(cameraRendered(solid(0.0)), .portra400))
        let reversal = meanLuma(look(cameraRendered(solid(0.0)), .velvia50))
        XCTAssertGreaterThan(negative, reversal,
                             "슬라이드가 네거티브 인화보다 검정이 깊어야 합니다.")
    }

    // MARK: 매체 대비 서열

    /// 노출 스케일이 유제 고유의 대비 서열을 지워서는 안 된다. 슬라이드는 네거티브 인화보다
    /// 대비가 높고, 각 그룹 안에서도 데이터시트 서열이 유지되어야 한다.
    func testExposureScaleKeepsContrastOrdering() {
        func gamma(_ film: FilmEmulation) -> Double {
            DigitalFilmDevelop.finalGamma(of: DigitalFilmPhysics.of(film)!)
        }
        XCTAssertGreaterThan(gamma(.velvia50), gamma(.provia100F),
                             "Velvia 가 Provia 보다 대비가 높아야 합니다.")
        XCTAssertGreaterThan(gamma(.provia100F), gamma(.ektachromeE100),
                             "Provia 가 E100 보다 대비가 높아야 합니다.")
        XCTAssertGreaterThan(gamma(.ektar100), gamma(.portra400),
                             "Ektar 가 Portra 400 보다 대비가 높아야 합니다.")
        XCTAssertGreaterThan(gamma(.portra400), gamma(.pro400H),
                             "PRO 400H 가 가장 연조여야 합니다.")
        let slide = FilmEmulation.films(of: .slide).map(gamma).reduce(0, +) / 3
        let negative = FilmEmulation.films(of: .negative).map(gamma)
        XCTAssertGreaterThan(slide, negative.reduce(0, +) / Double(negative.count),
                             "슬라이드가 네거티브 인화보다 대비가 높아야 합니다.")
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
