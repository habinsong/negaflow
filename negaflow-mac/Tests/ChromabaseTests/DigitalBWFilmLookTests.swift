import XCTest
import CoreImage
import CoreGraphics
import simd
@testable import Chromabase

// 디지털 소스 전용 흑백 필름 경로 검증.
//
// 실제 스캔을 열어 눈으로 보고 판단하지 않는다. 합성 패치를 넣고 나온 숫자로만 확인한다.
// 검증하는 것은 "예쁜가"가 아니라 유제 물성이 실제로 신호에 실렸는가다.
final class DigitalBWFilmLookTests: XCTestCase {

    private let allBWFilms: [FilmEmulation] = [
        .triX400, .hp5Plus, .fp4Plus, .delta100, .delta400, .delta3200,
        .tmax100, .tmax400, .tmaxP3200, .kentmere400, .orthoPlus,
        .sfx200, .rolleiIR, .scala200X, .rolleiSuperpan,
    ]

    // MARK: 이미지가 살아남는가 (이번 회귀의 가드)

    /// 흑백 룩이 유효한 extent 를 내야 한다.
    ///
    /// 없는 CIFilter 이름을 부르면 Core Image 는 원본이 아니라 **빈 이미지**를 돌려준다.
    /// 그러면 프레임이 통째로 사라지고 앱은 "이미지 로드 실패"만 보여 준다 — 원인이 렌더
    /// 파이프라인 안쪽이라 로그만으로는 추적이 어렵다. extent 를 직접 못 박아 둔다.
    func testEveryBWFilmProducesANonEmptyImage() {
        let patch = solidRGB(0.42, 0.26, 0.16)
        for film in allBWFilms {
            let out = DigitalBWFilmLook.apply(to: patch, emulation: film, intensity: 0.8,
                                              grainOverride: 0, halationOverride: 0)
            XCTAssertEqual(out.extent, patch.extent,
                           "\(film.displayName): 룩이 이미지를 소멸시켰습니다.")
            let px = render(out)
            XCTAssertFalse(px.r.isNaN || px.g.isNaN || px.b.isNaN,
                           "\(film.displayName): NaN 출력")
            XCTAssertGreaterThan(px.r, 0, "\(film.displayName): 출력이 비었습니다.")
        }
    }

    /// 엔진 전체를 지나도 마찬가지다. 스테이지 단위로만 확인하면 배선이 틀린 것을 놓친다.
    func testEngineProducesANonEmptyImageForEveryBWFilm() {
        let engine = ChromabaseEngine()
        let patch = solidRGB(0.42, 0.26, 0.16)
        for film in allBWFilms {
            var params = DevelopParameters()
            params.filmType = .bwPositive
            params.isDigitalSource = true
            params.filmEmulation = film
            params.filmEmulationIntensity = 0.8
            let px = render(engine.develop(image: patch, base: nil, params: params))
            XCTAssertGreaterThan(px.r, 0, "\(film.displayName): 현상 결과가 비었습니다.")
            XCTAssertFalse(px.r.isNaN, "\(film.displayName): NaN")
        }
    }

    // MARK: 중립성

    /// 흑백 유제에는 층이 하나뿐이라 색이 남을 자리가 없다. 그레인까지 지난 뒤에도 중립이어야 한다.
    func testOutputIsNeutralEvenAfterGrain() {
        let patch = solidRGB(0.55, 0.30, 0.20)
        for film in allBWFilms {
            let out = DigitalBWFilmLook.apply(to: patch, emulation: film, intensity: 1.0,
                                              grainOverride: 1.0, halationOverride: 0)
            let px = render(out)
            XCTAssertEqual(px.r, px.g, accuracy: 1e-4, "\(film.displayName): 그레인이 색을 남겼습니다.")
            XCTAssertEqual(px.g, px.b, accuracy: 1e-4, "\(film.displayName): 그레인이 색을 남겼습니다.")
        }
    }

    // MARK: 분광 감도 — 흑백 필름 룩의 1차 변수

    /// 오소크로매틱은 적색에 반응하지 않는다. 같은 빨강 패치가 팬크로보다 확실히 어두워야 한다.
    /// 반대로 적외 유제는 같은 패치를 밝게 띄운다. 이 둘이 뒤집히면 분광 축이 죽은 것이다.
    func testSpectralWeightsSeparateOrthoFromInfrared() {
        let red = solidRGB(0.60, 0.12, 0.10)
        let pan = gray(of: .triX400, patch: red)
        let ortho = gray(of: .orthoPlus, patch: red)
        let infrared = gray(of: .rolleiIR, patch: red)

        XCTAssertLessThan(ortho, pan * 0.7,
                          "오소가 빨강을 팬크로만큼 밝게 냈습니다 — 적색 무감도가 반영되지 않았습니다.")
        XCTAssertGreaterThan(infrared, pan * 1.2,
                             "적외 유제가 빨강을 팬크로보다 밝게 내지 않았습니다.")
    }

    /// 팬크로 유제는 사람 눈보다 청색에 과감하다(그래서 노란 필터를 쓴다). T-Max 계열만
    /// Kodak 이 청색 감도를 낮췄다고 명시하므로, 파란 패치에서 둘의 순서가 갈려야 한다.
    func testTMaxRendersBlueDarkerThanConventionalPanchromatic() {
        let blue = solidRGB(0.12, 0.20, 0.62)
        let triX = gray(of: .triX400, patch: blue)
        let tmax = gray(of: .tmax100, patch: blue)
        XCTAssertLessThan(tmax, triX * 0.92,
                          "T-Max 의 낮은 청색 감도가 반영되지 않았습니다.")
    }

    /// 분광 가중치는 합 1 로 정규화되어야 한다. 그러지 않으면 필름을 바꿀 때마다 노출이
    /// 달라 보이고, 그것은 유제의 성격이 아니라 구현의 실수다.
    func testSpectralWeightsAreNormalized() {
        for film in allBWFilms {
            guard let profile = BWFilmProfile.of(film) else { return XCTFail("\(film.displayName)") }
            let w = profile.spectralWeights
            XCTAssertEqual(w.x + w.y + w.z, 1.0, accuracy: 1e-9,
                           "\(film.displayName): 분광 가중치 합이 1 이 아닙니다.")
        }
    }

    /// 중성 회색에서는 분광 가중치가 상쇄되므로(합=1) 남는 차이는 톤 곡선뿐이다.
    /// 네거티브끼리는 인화지가 뒤를 받쳐 대비가 수렴하므로 흔들림이 좁아야 한다.
    /// 반전은 인화 단계가 없어 애초에 다른 대비로 렌더하는 것이 정상이라 여기서 제외한다.
    func testNeutralGrayStaysAnchoredAcrossNegativeFilms() {
        let neutral = solidRGB(0.45, 0.45, 0.45)
        let negatives = allBWFilms.filter { BWFilmProfile.of($0)?.isReversal == false }
        let values = negatives.map { gray(of: $0, patch: neutral) }
        let lo = values.min() ?? 0
        let hi = values.max() ?? 0
        XCTAssertLessThan(hi - lo, 0.10,
                          "중성 회색이 네거티브끼리도 크게 흔들립니다 — 노출 앵커가 깨졌습니다.")
        for (film, v) in zip(negatives, values) {
            XCTAssertGreaterThan(v, 0.2, "\(film.displayName): 중성 회색이 무너졌습니다.")
            XCTAssertLessThan(v, 0.8, "\(film.displayName): 중성 회색이 무너졌습니다.")
        }
    }

    // MARK: 특성곡선

    /// 긴 토우(전통 큐빅)는 암부를 들어 올리고, 곧은 토우(T-GRAIN)는 더 떨군다.
    func testLongToeLiftsShadowsMoreThanStraightLine() {
        let shadow = solidRGB(0.08, 0.08, 0.08)
        let longToe = gray(of: .triX400, patch: shadow)
        let straight = gray(of: .tmax100, patch: shadow)
        XCTAssertGreaterThan(longToe, straight,
                             "긴 토우가 곧은 토우보다 암부를 들어 올리지 않았습니다.")
    }

    /// 반전은 인화지가 뒤를 받치지 않아 대비가 훨씬 세다. 같은 두 밝기의 간격으로 측정한다.
    func testReversalHasHigherContrastThanNegative() {
        let dark = solidRGB(0.18, 0.18, 0.18)
        let light = solidRGB(0.72, 0.72, 0.72)
        func spread(_ film: FilmEmulation) -> Double {
            gray(of: film, patch: light) - gray(of: film, patch: dark)
        }
        XCTAssertGreaterThan(spread(.scala200X), spread(.triX400),
                             "흑백 반전이 네거티브보다 대비가 높지 않습니다.")
    }

    /// 반전은 검정이 더 깊다 — 뒤에서 받쳐 주는 인화지 바닥이 없기 때문이다.
    func testReversalReachesDeeperBlacks() {
        let shadow = solidRGB(0.06, 0.06, 0.06)
        XCTAssertLessThan(gray(of: .scala200X, patch: shadow),
                          gray(of: .triX400, patch: shadow),
                          "흑백 반전의 검정이 네거티브보다 깊지 않습니다.")
    }

    // MARK: 강도

    /// 강도 0 이면 유제 특성이 사라지고 중립 휘도 그레이만 남아야 한다. 이것이 강도의 정의다.
    func testZeroIntensityFallsBackToNeutralLuminance() {
        let patch = solidRGB(0.60, 0.12, 0.10)
        let neutral = 0.2126 * 0.60 + 0.7152 * 0.12 + 0.0722 * 0.10
        for film in [FilmEmulation.orthoPlus, .rolleiIR, .scala200X] {
            let out = DigitalBWFilmLook.apply(to: patch, emulation: film, intensity: 0.002,
                                              grainOverride: 0, halationOverride: 0)
            let px = render(out)
            XCTAssertEqual(px.r, neutral, accuracy: 0.02,
                           "\(film.displayName): 강도 0 에서 중립으로 돌아가지 않았습니다.")
        }
    }

    /// 강도를 올릴수록 유제 특성이 단조롭게 강해져야 한다. 중간에서 뒤집히면 슬라이더가
    /// 사용자에게 거짓말을 하는 것이다.
    func testIntensityIsMonotonic() {
        let red = solidRGB(0.60, 0.12, 0.10)
        let neutral = 0.2126 * 0.60 + 0.7152 * 0.12 + 0.0722 * 0.10
        var previous = 0.0
        for step in [0.25, 0.5, 0.75, 1.0] {
            let out = DigitalBWFilmLook.apply(to: red, emulation: .orthoPlus, intensity: step,
                                              grainOverride: 0, halationOverride: 0)
            let distance = abs(render(out).r - neutral)
            XCTAssertGreaterThan(distance, previous,
                                 "강도 \(step) 에서 유제 특성이 더 강해지지 않았습니다.")
            previous = distance
        }
    }

    // MARK: 라우팅 — 디지털 소스 전용, 프로세스에 맞는 종류만

    /// 필름 스캔 경로에는 필름 룩이 걸리지 않는다. 스캔본에는 이미 그 유제를 통과한 신호가
    /// 들어 있어 유제 응답을 두 번 먹이게 되기 때문이다.
    func testFilmScanPathGetsNoFilmLook() {
        let engine = ChromabaseEngine()
        let patch = solidRGB(0.42, 0.26, 0.16)
        for (filmType, film) in [(FilmType.bwPositive, FilmEmulation.triX400),
                                 (.bwNegative, .hp5Plus),
                                 (.colorPositive, .velvia50),
                                 (.colorNegative, .portra400)] {
            func develop(_ emulation: FilmEmulation) -> (r: Double, g: Double, b: Double) {
                var params = DevelopParameters()
                params.filmType = filmType
                params.isDigitalSource = false
                params.filmEmulation = emulation
                params.filmEmulationIntensity = 1.0
                return render(engine.develop(image: patch, base: nil, params: params))
            }
            assertClose(develop(film), develop(.none), accuracy: 1e-6,
                        "\(filmType): 필름 스캔 경로에 필름 룩이 걸렸습니다.")
        }
    }

    /// 프로세스와 유제 종류가 어긋나면 룩이 걸리지 않는다. 프로세스를 바꿔도 선택은 보존되므로
    /// 목록에 없는 필름이 파라미터에 남아 있을 수 있고, 그때 엉뚱한 룩이 걸리면 안 된다.
    func testMismatchedFilmKindIsIgnored() {
        let engine = ChromabaseEngine()
        let patch = solidRGB(0.42, 0.26, 0.16)
        func develop(filmType: FilmType, film: FilmEmulation) -> (r: Double, g: Double, b: Double) {
            var params = DevelopParameters()
            params.filmType = filmType
            params.isDigitalSource = true
            params.filmEmulation = film
            params.filmEmulationIntensity = 1.0
            return render(engine.develop(image: patch, base: nil, params: params))
        }
        // Digital Color 에 흑백 유제를 남겨 두어도 컬러 결과가 달라지지 않는다.
        assertClose(develop(filmType: .colorPositive, film: .triX400),
                    develop(filmType: .colorPositive, film: .none),
                    accuracy: 1e-6, "Digital Color 에서 흑백 유제가 걸렸습니다.")
        // Digital B&W 에 컬러 유제를 남겨 두어도 흑백 결과가 달라지지 않는다.
        assertClose(develop(filmType: .bwPositive, film: .velvia50),
                    develop(filmType: .bwPositive, film: .none),
                    accuracy: 1e-6, "Digital B&W 에서 컬러 유제가 걸렸습니다.")

        XCTAssertFalse(DigitalFilmLook.appliesLook(emulation: .triX400, monochrome: false))
        XCTAssertFalse(DigitalFilmLook.appliesLook(emulation: .velvia50, monochrome: true))
        XCTAssertTrue(DigitalFilmLook.appliesLook(emulation: .triX400, monochrome: true))
        XCTAssertTrue(DigitalFilmLook.appliesLook(emulation: .vision3_500T, monochrome: false))
        XCTAssertFalse(DigitalFilmLook.appliesLook(emulation: .none, monochrome: true))
        XCTAssertFalse(DigitalFilmLook.appliesLook(emulation: .none, monochrome: false))
    }

    /// 흑백 유제는 흑백 테이블에만, 컬러 유제는 컬러 테이블에만 있어야 한다.
    func testProfileTablesDoNotOverlap() {
        for film in allBWFilms {
            XCTAssertNotNil(BWFilmProfile.of(film), "\(film.displayName): 흑백 프로파일이 없습니다.")
            XCTAssertNil(DigitalFilmPhysics.of(film),
                         "\(film.displayName): 컬러 물리 테이블에 흑백 유제가 들어 있습니다.")
        }
        for film in FilmEmulation.allCases where film.kind == .slide || film.kind == .negative
            || film.kind == .motionPicture {
            XCTAssertNil(BWFilmProfile.of(film),
                         "\(film.displayName): 흑백 테이블에 컬러 유제가 들어 있습니다.")
            XCTAssertNotNil(DigitalFilmPhysics.of(film),
                            "\(film.displayName): 컬러 물리 파라미터가 없습니다.")
        }
    }

    /// 모든 흑백 유제가 서로 구별되어야 한다. 목록만 늘고 결과가 같으면 UI 가 거짓말이 된다.
    ///
    /// 다만 구별의 축이 톤 하나뿐인 것은 아니다. T-Max 100 과 400 은 실제로 톤 응답이 거의
    /// 같고 갈리는 곳은 입상성(RMS 8 대 10)과 해상력이다 — 톤만 비교하면 "같은 필름"이라는
    /// 틀린 결론이 나온다. 그래서 유제를 특징짓는 축을 함께 본다.
    func testEveryBWFilmIsDistinguishable() {
        let patch = solidRGB(0.52, 0.34, 0.22)
        var seen: [(FilmEmulation, [Double])] = []
        for film in allBWFilms {
            guard let profile = BWFilmProfile.of(film) else { return XCTFail("\(film.displayName)") }
            let signature = [
                gray(of: film, patch: patch),
                profile.grainAmplitude,
                profile.grainSize,
                profile.acutance.intensity,
                profile.halationStrength,
            ]
            for (other, otherSignature) in seen {
                let distance = zip(signature, otherSignature).map { abs($0 - $1) }.max() ?? 0
                XCTAssertGreaterThan(
                    distance, 1e-3,
                    "\(film.displayName) 과 \(other.displayName) 이 구별되지 않습니다."
                )
            }
            seen.append((film, signature))
        }
    }

    // MARK: 헬퍼

    /// 그레인·헐레이션을 끄고 유제 응답만 본다. 난수가 섞이면 측정이 흔들린다.
    private func gray(of film: FilmEmulation, patch: CIImage) -> Double {
        guard let profile = BWFilmProfile.of(film) else { return .nan }
        var stripped = profile
        stripped.grainAmplitude = 0
        stripped.halationStrength = 0
        stripped.scatterStrength = 0
        stripped.acutance = (0, 0)
        return render(responseOnly(patch, profile: stripped)).r
    }

    private func responseOnly(_ image: CIImage, profile: BWFilmProfile) -> CIImage {
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "digitalBWFilm") else {
            return image
        }
        let r = BWFilmResponse(profile: profile, intensity: 1.0)
        return kernel.apply(
            extent: image.extent,
            arguments: [
                image,
                CIVector(x: CGFloat(r.weights.x), y: CGFloat(r.weights.y),
                         z: CGFloat(r.weights.z), w: 1.0),
                CIVector(x: CGFloat(r.contrast), y: CGFloat(r.toe),
                         z: CGFloat(r.shoulder), w: CGFloat(r.deepen)),
                CIVector(x: CGFloat(r.black), y: CGFloat(r.white), z: 0, w: 0),
            ]
        )?.cropped(to: image.extent) ?? image
    }

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

    private func render(_ image: CIImage, w: Int = 64, h: Int = 64) -> (r: Double, g: Double, b: Double) {
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

    private func assertClose(_ a: (r: Double, g: Double, b: Double),
                             _ b: (r: Double, g: Double, b: Double),
                             accuracy: Double, _ message: String) {
        XCTAssertEqual(a.r, b.r, accuracy: accuracy, message)
        XCTAssertEqual(a.g, b.g, accuracy: accuracy, message)
        XCTAssertEqual(a.b, b.b, accuracy: accuracy, message)
    }
}
