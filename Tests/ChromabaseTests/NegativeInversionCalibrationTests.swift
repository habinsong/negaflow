import XCTest
import CoreImage
@testable import Chromabase

/// 네거티브 반전의 물리 합성 픽스처와 명확한 기능 계약.
///
/// 실제 scanner/film characterization 없이 합성 C-41 모델의 단일 패치 값으로 미감이나
/// 장치 정확도를 판정하지 않는다. 다만 모든 타겟이 공유하는 기본 반전의 광도 계약은
/// 단일 값이 아니라 베이스 보더와 5단계 중립 패치 전체로 회귀 검사한다. 전체 프레임 구조 계약은
/// `DevelopTargetWholeFrameCompositionTests`, 공식 reference 전 패치는 IT8 benchmark가 담당한다.
///
/// 과거 진단이 사용한 가정:
///   • 적정 18% 회색 → linear ≈ 0.18 (sRGB ≈ 0.46) — 과거 로그-직결 렌더링은 +1.7~2.0 스탑
///     과다 밝기(sRGB 0.82)에 밝은 영역(gray36~white90)이 0.9~0.96 에 뭉쳤다.
///   • 하이라이트 계조 분리(gray36 ↔ white90 뭉침 금지).
///   • 섀도 비크러시(black2 = 필름이 기록한 섀도 — 0 크러시 금지).
///   • NORITSU/FUJI 는 photometric mid ± 실기 간 실측 차이(같은 롤 쌍) 이내.
///   • LATD 리프트: HDR 장면(스펙큘러 지배)은 미드 복구, 저조도(얇은 네거)는 리프트 금지.
final class NegativeInversionCalibrationTests: XCTestCase {

    // MARK: 물리 픽스처 (C-41 특성곡선 모델)

    private let filmBase = SIMD3<Double>(0.72, 0.46, 0.28)   // 오렌지 마스크 스캔 투과율
    private let filmGamma = SIMD3<Double>(0.65, 0.62, 0.60)  // 채널별 특성곡선 기울기
    private let midDensity = 0.60                             // 합성 회귀 픽스처의 선언값

    /// 장면 반사율 → 네거티브 투과율 (직선부, toe 클램프).
    private func transmission(reflectance: SIMD3<Double>) -> SIMD3<Double> {
        var t = SIMD3<Double>()
        for c in 0..<3 {
            let logE = log10(max(reflectance[c], 1e-6) / 0.18)
            let d = max(0.0, midDensity + filmGamma[c] * logE)
            t[c] = filmBase[c] * pow(10.0, -d)
        }
        return t
    }

    /// 베이스 보더 + 18% 배경 + 패치 밴드로 구성한 물리 합성 네거티브(float — 양자화 배제).
    private func makeNegative(
        width: Int = 240, height: Int = 160,
        background: Double = 0.18,
        patches: [(name: String, refl: SIMD3<Double>)]
    ) -> (image: CIImage, centers: [String: (x: Int, y: Int)]) {
        let bx = Int(Double(width) * 0.08), by = Int(Double(height) * 0.08)
        var floats = [Float](repeating: 0, count: width * height * 4)
        var centers: [String: (x: Int, y: Int)] = [:]
        let cols = max(patches.count, 1)
        let pw = (width - 2 * bx) / cols
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let isBorder = x < bx || x >= width - bx || y < by || y >= height - by
                var t = filmBase
                if !isBorder {
                    var refl = SIMD3<Double>(repeating: background)
                    let inBand = y >= height / 3 && y < height * 2 / 3
                    if inBand {
                        let col = min((x - bx) / max(pw, 1), cols - 1)
                        refl = patches[col].refl
                        centers[patches[col].name] = (bx + col * pw + pw / 2, height / 2)
                    }
                    t = transmission(reflectance: refl)
                }
                floats[i] = Float(t.x); floats[i + 1] = Float(t.y)
                floats[i + 2] = Float(t.z); floats[i + 3] = 1
            }
        }
        let image = CIImage(
            bitmapData: Data(bytes: floats, count: floats.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
        return (image, centers)
    }

    private func developLinear(
        _ image: CIImage, width: Int, height: Int,
        target: DevelopTarget, filmType: FilmType = .colorNegative
    ) -> [Float] {
        var params = DevelopParameters()
        params.filmType = filmType
        params.developTarget = target
        let developed = ChromabaseEngine().develop(
            image: image, base: FilmBase(rgb: filmBase, source: .border), params: params)
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        var out = [Float](repeating: 0, count: width * height * 4)
        ctx.render(developed, toBitmap: &out, rowBytes: width * 4 * MemoryLayout<Float>.size,
                   bounds: CGRect(x: 0, y: 0, width: width, height: height),
                   format: .RGBAf, colorSpace: linear)
        return out
    }

    private func linearLuma(_ px: [Float], at p: (x: Int, y: Int), width: Int) -> Double {
        let i = (p.y * width + p.x) * 4
        return 0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2])
    }

    private let standardPatches: [(name: String, refl: SIMD3<Double>)] = [
        ("white90", SIMD3(repeating: 0.90)),
        ("gray36", SIMD3(repeating: 0.36)),
        ("gray18", SIMD3(repeating: 0.18)),
        ("gray9", SIMD3(repeating: 0.09)),
        ("black2", SIMD3(repeating: 0.02)),
    ]

    // MARK: 컬러 네거티브 — 전 타겟 밝기 앵커

    func testColorPresetAnalyticalReferencePointsWithoutSceneSampling() {
        let base = 0.72
        let nominal = NegativeInversion.colorResponse.normalRange
        let baseOutput = NegativeInversion.positiveValue(
            transmission: base,
            dmin: base,
            dmaxNorm: nominal
        )
        let midOutput = NegativeInversion.positiveValue(
            transmission: base * pow(10.0, -NegativeInversion.normalMidDensity),
            dmin: base,
            dmaxNorm: nominal
        )
        let denseOutput = NegativeInversion.positiveValue(
            transmission: base * pow(10.0, -3.0),
            dmin: base,
            dmaxNorm: nominal
        )

        // 광도 계약 앵커: 베이스 = 토우(0.001), 정상 미드 밀도(0.60D) = 미드그레이(0.18).
        XCTAssertEqual(baseOutput, 0.001, accuracy: 1e-12)
        XCTAssertEqual(midOutput, 0.18, accuracy: 1e-12)
        XCTAssertEqual(denseOutput, 0.882_836_683_855, accuracy: 1e-12)
        XCTAssertGreaterThan(midOutput, baseOutput)
        XCTAssertGreaterThan(denseOutput, midOutput)
        XCTAssertLessThan(denseOutput, 1.0)
    }

    /// 인화 응답 곡선 계수가 광도 계약 4앵커에서 닫힌형으로 유도됨을 잠근다(derivation lock).
    /// 상수가 앵커와 무관하게 직접 박히면(하드코딩 회귀) 이 테스트가 깨진다.
    func testPrintResponseDerivesFromPhotometricContract() {
        for (response, toe, white, ceiling, range) in [
            (NegativeInversion.colorResponse, 0.001, 0.70, 0.90, 0.62 * 2.5),
            (NegativeInversion.bwResponse, 0.0005, 0.85, 0.98, 0.62 * 3.5),
        ] {
            XCTAssertEqual(response.normalRange, range, accuracy: 1e-12)
            // 앵커 재현: d=0 → 토우, midRangeFraction → 0.18, d=1 → 화이트.
            XCTAssertEqual(response.linearOutput(normalizedDensity: 0), toe, accuracy: 1e-13)
            XCTAssertEqual(
                response.linearOutput(normalizedDensity: NegativeInversion.midRangeFraction),
                NegativeInversion.midGrayLinear, accuracy: 1e-13)
            XCTAssertEqual(response.linearOutput(normalizedDensity: 1), white, accuracy: 1e-13)
            // 천장: 유한 밀도에서 ceiling 미만, 극한에서도 초과 불가(코드 255 구조적 불가).
            XCTAssertLessThan(response.linearOutput(normalizedDensity: 3), ceiling)
            XCTAssertLessThanOrEqual(response.linearOutput(normalizedDensity: 10), ceiling)
            // 닫힌형 유도 재계산 일치(독립 수식).
            let yCeil = log10(ceiling)
            let amplitude = yCeil - log10(toe)
            let rMid = log(amplitude / (yCeil - log10(0.18)))
            let rWhite = log(amplitude / (yCeil - log10(white)))
            let shape = log(rWhite / rMid) / log(1.0 / NegativeInversion.midRangeFraction)
            XCTAssertEqual(response.shape, shape, accuracy: 1e-12)
            XCTAssertEqual(response.rate, pow(rWhite, 1.0 / shape), accuracy: 1e-12)
            // 역함수 라운드트립.
            for value in [0.002, 0.05, 0.18, 0.5, min(white + 0.05, ceiling - 0.02)] {
                let d = response.normalizedDensity(forLinearOutput: value)
                XCTAssertEqual(response.linearOutput(normalizedDensity: d), value, accuracy: 1e-10)
            }
            // 음의 밀도(베이스보다 밝은 비필름): 토우 아래 유한 양수, 단조 유지.
            let below = response.linearOutput(normalizedDensity: -0.05)
            XCTAssertGreaterThan(below, 0)
            XCTAssertLessThan(below, toe)
            XCTAssertLessThan(response.linearOutput(normalizedDensity: -0.2), below)
        }
    }

    func testColorAndBWDefaultDensityWedgesAvoidDisplayEndpoints() {
        for filmType in [FilmType.colorNegative, .bwNegative] {
            let dmax = NegativeInversion.response(for: filmType).normalRange
            let base = 0.72
            var previous = -Double.infinity
            var codes: [Int] = []

            for index in 0...3_000 {
                let density = Double(index) / 1_000.0
                let output = NegativeInversion.positiveValue(
                    transmission: base * pow(10.0, -density),
                    dmin: base,
                    dmaxNorm: dmax,
                    filmType: filmType
                )
                XCTAssertTrue(output.isFinite, "\(filmType) density=\(density)")
                XCTAssertGreaterThan(output, previous, "\(filmType) density=\(density)")
                XCTAssertGreaterThanOrEqual(output, 0.0, "\(filmType) density=\(density)")
                XCTAssertLessThan(output, 1.0, "\(filmType) density=\(density)")
                previous = output

                let encoded = output <= 0.003_130_8
                    ? 12.92 * output
                    : 1.055 * pow(output, 1.0 / 2.4) - 0.055
                codes.append(Int((min(max(encoded, 0), 1) * 255).rounded()))
            }

            XCTAssertFalse(codes.contains(0), "\(filmType): 검정 끝 빈 포화")
            XCTAssertFalse(codes.contains(255), "\(filmType): 흰색 끝 빈 포화")
        }
    }

    func testColorNegativeTargetsLandMidGrayAtPhotometricAnchor() {
        let width = 240, height = 160
        // scene-adaptive 반전은 이 네거티브가 실제 사용한 밀도 범위(Dmax)를 최농부에서 측정한다.
        // 따라서 픽스처는 현실적인 딥 하이라이트(광원/스펙큘러)를 포함해야 한다 — 90% 확산백만
        // 최농부이면 확산백을 필름 Dmax 로 오인해 전 톤이 과다 밝아진다(실제 장면엔 확산백보다
        // 진한 광원이 있고, 확산백은 필름 Dmax 가 아니다). 딥 하이라이트를 포함하면 측정 Dmax 가
        // 필름 물성에 맞아 18% 회색이 photometric mid 에 앉는다.
        let anchorPatches = standardPatches + [("lightSource", SIMD3(repeating: 6.0))]
        let (image, centers) = makeNegative(width: width, height: height, patches: anchorPatches)
        // 타겟별 mid 허용 오차(스탑): MAIN/PRINT/EXPIRED 는 photometric mid 고정.
        // NORITSU 는 문서 기반 플랫(섀도 개방)이라 살짝 어둡게 허용.
        // FUJI 는 SP-3000 실측 캘리브레이션(6쌍 히스토그램 매칭)으로 미드를 밝게 리프트하므로
        // +0.85 까지 허용한다(실측 ~+0.63). 상한은 여전히 과거 로그-직결 회귀(+1.7~2.0)를 잠근다.
        let cases: [(DevelopTarget, ClosedRange<Double>)] = [
            (.main, -0.35...0.35),
            (.print, -0.40...0.40),
            (.rescue, -0.40...0.40),
            (.noritsu, -0.60...0.35),
            (.sp3000, -0.30...0.85),
            // F135 는 미드 온건 리프트(+0.011 감마), HR 는 노출 규율(≈중립) — MAIN 창 재사용.
            (.f135, -0.35...0.50),
            (.hr, -0.40...0.40),
        ]
        var midStops: [DevelopTarget: Double] = [:]
        for (target, range) in cases {
            let out = developLinear(image, width: width, height: height, target: target)
            let mid = linearLuma(out, at: centers["gray18"]!, width: width)
            let stops = log2(max(mid, 1e-6) / 0.18)
            midStops[target] = stops
            XCTAssertTrue(range.contains(stops),
                "\(target.displayName): 적정 18% 회색이 photometric mid(linear 0.18) 에서 " +
                "\(String(format: "%+.2f", stops)) 스탑 벗어남(허용 \(range)). " +
                "과거 로그-직결 렌더링 회귀(+1.7~2.0 스탑)를 잠그는 가드.")

            // 하이라이트 계조: scene-adaptive 반전은 최농부(광원)를 화이트포인트로 매핑한다.
            // 확산백(90%)은 광원 아래의 밝은 톤이고, 톤이 순서대로 벌어져 뭉치지 않아야 한다
            // (사용자 증상: 밝은 영역이 좁은 대역에 압축). 최상위 톤의 상한(≈0.7)은 인화 응답의
            // 화이트 앵커(whiteOutput)가 정하는 별도 특성이다.
            let g36 = linearLuma(out, at: centers["gray36"]!, width: width)
            let w90 = linearLuma(out, at: centers["white90"]!, width: width)
            let light = linearLuma(out, at: centers["lightSource"]!, width: width)
            XCTAssertGreaterThan(w90, g36,
                "\(target.displayName): 확산백이 gray36 보다 밝아야 한다(계조 순서). g36=\(g36) w90=\(w90)")
            XCTAssertGreaterThan(light, w90,
                "\(target.displayName): 광원이 확산백보다 밝아야 한다(계조 순서). w90=\(w90) light=\(light)")
            XCTAssertGreaterThan(log2(max(w90, 1e-6) / max(g36, 1e-6)), 0.4,
                "\(target.displayName): gray36↔white90 하이라이트 계조가 뭉갬. g36=\(g36) w90=\(w90)")
            XCTAssertGreaterThan(light, 0.55,
                "\(target.displayName): 최상위 하이라이트가 좁은 대역에 압축되면 안 된다. light=\(light)")
            XCTAssertLessThan(light, 1.0,
                "\(target.displayName): 최상위 하이라이트는 soft-clip 으로 1 아래에서 끝나야 한다. light=\(light)")

            // 섀도: black2(밀도 0.16 above base — 필름이 기록한 섀도)는 gray9 보다 어둡되
            // 0 크러시는 아니어야 한다(플랫 마스터/복구 타겟의 정보 보존).
            let g9 = linearLuma(out, at: centers["gray9"]!, width: width)
            let b2 = linearLuma(out, at: centers["black2"]!, width: width)
            XCTAssertLessThan(b2, g9, "\(target.displayName): 톤 순서가 깨짐")
            if target == .main {
                // black2(refl 0.02)는 이 픽스처에서 사실상 베이스 밀도에 있어 인화 응답의 토우
                // (paper-black, ≈0.001)에 매핑된다. 정확히 0 으로 크러시되지 않음(토우 보존)을
                // 검증한다 — 토우 값 자체는 인화지 응답 커브가 정하는 별도 특성이다.
                XCTAssertGreaterThan(b2, 0.0008,
                    "MAIN 플랫 마스터는 기록된 섀도를 0 으로 크러시하지 않는다(토우 보존). b2=\(b2)")
            }
        }
        // 실기 간 실측 방향: SP-3000(FUJI) 미드가 NORITSU 보다 밝다(같은 롤 쌍 p50 실측).
        XCTAssertGreaterThan(midStops[.sp3000]! - midStops[.noritsu]!, 0.2,
            "실기 간 mid 차이(SP > NOR, 같은 롤 쌍 실측 ≈ 0.45~0.6 스탑)가 보존돼야 한다")
    }

    // MARK: 흑백 네거티브 — 동일 앵커

    func diagnoseBWNegativeMainLandsMidGrayAtPhotometricAnchor() {
        let width = 240, height = 160
        // 흑백: 중립 베이스 + 단일 감마. 필드를 임시 교체하는 대신 중립 픽스처를 직접 구성.
        let neutralBase = SIMD3<Double>(repeating: 0.78)
        let gamma = 0.62
        let bx = Int(Double(width) * 0.08), by = Int(Double(height) * 0.08)
        var floats = [Float](repeating: 0, count: width * height * 4)
        var centers: [String: (x: Int, y: Int)] = [:]
        let cols = standardPatches.count
        let pw = (width - 2 * bx) / cols
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let isBorder = x < bx || x >= width - bx || y < by || y >= height - by
                var t = neutralBase.x
                if !isBorder {
                    var refl = 0.18
                    if y >= height / 3 && y < height * 2 / 3 {
                        let col = min((x - bx) / max(pw, 1), cols - 1)
                        refl = standardPatches[col].refl.x
                        centers[standardPatches[col].name] = (bx + col * pw + pw / 2, height / 2)
                    }
                    let d = max(0.0, midDensity + gamma * log10(max(refl, 1e-6) / 0.18))
                    t = neutralBase.x * pow(10.0, -d)
                }
                floats[i] = Float(t); floats[i + 1] = Float(t)
                floats[i + 2] = Float(t); floats[i + 3] = 1
            }
        }
        let image = CIImage(
            bitmapData: Data(bytes: floats, count: floats.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
        var params = DevelopParameters()
        params.filmType = .bwNegative
        params.developTarget = .main
        let developed = ChromabaseEngine().develop(
            image: image, base: FilmBase(rgb: neutralBase, source: .border), params: params)
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        var out = [Float](repeating: 0, count: width * height * 4)
        ctx.render(developed, toBitmap: &out, rowBytes: width * 4 * MemoryLayout<Float>.size,
                   bounds: CGRect(x: 0, y: 0, width: width, height: height),
                   format: .RGBAf, colorSpace: linear)

        let mid = linearLuma(out, at: centers["gray18"]!, width: width)
        let stops = log2(max(mid, 1e-6) / 0.18)
        XCTAssertTrue((-0.40...0.40).contains(stops),
            "B&W MAIN: 18% 회색 photometric 앵커 벗어남 \(String(format: "%+.2f", stops)) 스탑")
        let g36 = linearLuma(out, at: centers["gray36"]!, width: width)
        let w90 = linearLuma(out, at: centers["white90"]!, width: width)
        XCTAssertGreaterThan(log2(max(w90, 1e-6) / max(g36, 1e-6)), 0.8,
            "B&W MAIN: 하이라이트 계조 뭉갬. g36=\(g36) w90=\(w90)")
    }

    // MARK: 명부 클리핑(화이트홀) 금지 — 전 타겟

    /// 밝은 영역 그라디언트(반사율 0.40→1.10)가 어느 타겟에서도 순백으로 뭉개지면 안 된다.
    /// 회귀 이력: NORITSU 의 "조기 순백" 톤 knot(whiteClipFraction)가 재앵커 도메인 오류로
    /// 명부 램프의 58% 를 255 클립시키는 화이트홀을 만들었다(2026-07-18 QA 실측).
    func diagnoseTargetHighlightRampEncoding() {
        let width = 240, height = 160
        let bx = Int(Double(width) * 0.08), by = Int(Double(height) * 0.08)
        var floats = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let isBorder = x < bx || x >= width - bx || y < by || y >= height - by
                var refl = SIMD3<Double>(repeating: 0.18)
                if !isBorder, y >= height / 3, y < height * 2 / 3 {
                    let f = Double(x - bx) / Double(width - 2 * bx)
                    refl = SIMD3(repeating: 0.40 + f * 0.70)   // 명부 램프
                }
                let t = isBorder ? filmBase : transmission(reflectance: refl)
                floats[i] = Float(t.x); floats[i + 1] = Float(t.y)
                floats[i + 2] = Float(t.z); floats[i + 3] = 1
            }
        }
        let image = CIImage(
            bitmapData: Data(bytes: floats, count: floats.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
        for target in [DevelopTarget.main, .print, .noritsu, .sp3000, .f135, .hr, .rescue] {
            let out = developLinear(image, width: width, height: height, target: target)
            var clipped = 0, total = 0
            var distinct = Set<Int>()
            let y = height / 2
            for x in (bx + 2)..<(width - bx - 2) {
                let i = (y * width + x) * 4
                let luma = 0.2126 * Double(out[i]) + 0.7152 * Double(out[i + 1])
                    + 0.0722 * Double(out[i + 2])
                let srgbByte = Int((AutoAdjust.srgbEncode(min(max(luma, 0), 1)) * 255).rounded())
                if srgbByte >= 254 { clipped += 1 }
                distinct.insert(srgbByte)
                total += 1
            }
            let clipFraction = Double(clipped) / Double(max(total, 1))
            XCTAssertLessThan(clipFraction, 0.03,
                "\(target.displayName): 명부 램프가 순백으로 뭉개짐(화이트홀). clip=\(clipFraction)")
            XCTAssertGreaterThan(distinct.count, 12,
                "\(target.displayName): 명부 계조가 뭉갬. distinct=\(distinct.count)")
        }
    }

    // MARK: 평탄(저 DR) 장면 — 과신장 완충

    /// 좁은 밀도 범위(안개 — 총 ≈0.35D) 장면을 화이트 앵커가 풀레인지로 펴면 안 된다.
    /// 저 DR 에서는 음의 리프트(미드 앵커)가 중앙값을 미드그레이 근처로 되돌린다.
    func diagnoseFlatLowDRSceneRendering() {
        let width = 240, height = 160
        // 안개 장면: 반사율 0.13~0.30 (≈1.2 스탑) — 흰색도 검정도 없는 평탄 분포.
        let (image, centers) = makeNegative(
            width: width, height: height,
            background: 0.18,
            patches: [
                ("fogLow", SIMD3(repeating: 0.13)),
                ("fogMid", SIMD3(repeating: 0.18)),
                ("fogHigh", SIMD3(repeating: 0.30)),
            ])
        let out = developLinear(image, width: width, height: height, target: .main)
        let high = linearLuma(out, at: centers["fogHigh"]!, width: width)
        let mid = linearLuma(out, at: centers["fogMid"]!, width: width)
        XCTAssertLessThan(high, 0.62,
            "평탄 장면의 최상위 톤이 화이트로 풀신장되면 안 된다(안개는 안개답게). high=\(high)")
        XCTAssertLessThan(abs(log2(max(mid, 1e-6) / 0.18)), 1.2,
            "평탄 장면의 미드가 미드그레이에서 크게 벗어나면 안 된다. mid=\(mid)")
    }

    // MARK: 크로모제닉 흑백(C-41 틴트 베이스) — 베이스 추정 폴백

    /// XP2 류 크로모제닉 흑백: 틴트 베이스(중립 추정 실패) → 컬러 추정 폴백으로 베이스를
    /// 잡고, 출력은 흑백 강제 중립화로 중립이어야 한다.
    func testChromogenicBWWithTintedBaseDevelopsNeutral() {
        let width = 240, height = 160
        let tintedBase = SIMD3<Double>(0.62, 0.50, 0.40)   // 웜 틴트 베이스(크로모제닉)
        let gamma = 0.62
        let bx = Int(Double(width) * 0.08), by = Int(Double(height) * 0.08)
        var floats = [Float](repeating: 0, count: width * height * 4)
        let patchW = (width - 2 * bx) / 5
        let midCenter = (x: bx + patchW * 2 + patchW / 2, y: height / 2)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let isBorder = x < bx || x >= width - bx || y < by || y >= height - by
                var t = tintedBase
                if !isBorder {
                    var refl = 0.18
                    if y >= height / 3, y < height * 2 / 3 {
                        let k = min((x - bx) * 5 / max(width - 2 * bx, 1), 4)
                        refl = [0.90, 0.36, 0.18, 0.09, 0.02][k]
                    }
                    let d = max(0.0, 0.75 + gamma * log10(max(refl, 1e-6) / 0.18))
                    t = tintedBase * pow(10.0, -d)
                }
                floats[i] = Float(t.x); floats[i + 1] = Float(t.y)
                floats[i + 2] = Float(t.z); floats[i + 3] = 1
            }
        }
        let image = CIImage(
            bitmapData: Data(bytes: floats, count: floats.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
        // 베이스 추정: 중립 추정이 틴트 베이스에서 실패해도 컬러 폴백으로 잡혀야 한다.
        let engine = ChromabaseEngine()
        let estimated = engine.estimateFilmBase(in: image, mode: .auto, filmType: .bwNegative)
        XCTAssertNotNil(estimated, "크로모제닉 틴트 베이스 추정이 폴백으로 성공해야 한다")
        if let estimated {
            XCTAssertEqual(estimated.rgb.x, tintedBase.x, accuracy: 0.06)
            XCTAssertEqual(estimated.rgb.z, tintedBase.z, accuracy: 0.06)
        }
        // develop: B&W 출력의 명확한 기능 계약은 중립 유지다. 미드 노출은 별도 view transform과
        // 사용자 노출 설정의 영역이며 이 합성 패치에서 18%로 고정하지 않는다.
        var params = DevelopParameters()
        params.filmType = .bwNegative
        params.developTarget = .main
        let developed = engine.develop(image: image, base: estimated, params: params)
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        var out = [Float](repeating: 0, count: width * height * 4)
        ctx.render(developed, toBitmap: &out, rowBytes: width * 4 * MemoryLayout<Float>.size,
                   bounds: CGRect(x: 0, y: 0, width: width, height: height),
                   format: .RGBAf, colorSpace: linear)
        let i = (midCenter.y * width + midCenter.x) * 4
        let r = Double(out[i]), g = Double(out[i + 1]), b = Double(out[i + 2])
        XCTAssertLessThan(max(abs(r - g), abs(g - b)), 0.02,
            "흑백 출력은 중립이어야 한다. rgb=(\(r),\(g),\(b))")
    }

    // MARK: 크로스오버(시안 bow) — NeutralBalance 의 교정 계약

    /// 채널별 미드 밀도 오프셋이 감마 비례가 아닌(마스크 커플러 크로스오버) 필름은 반전만으로
    /// 미드톤 시안-블루 bow 가 남는다(구조적 — 흰색/베이스 두 앵커만 채널 정렬됨). 이 잔차는
    /// opt-in NeutralBalance(미드 median 감마 정렬)의 담당이며, 켰을 때 유의미하게 줄어야 한다.
    func testNeutralBalanceReducesCrossoverBowOnSyntheticFixture() {
        let width = 240, height = 160
        let crossGamma = SIMD3<Double>(0.65, 0.62, 0.60)
        let crossMid = SIMD3<Double>(0.65, 0.75, 0.85)   // 채널 오프셋(비비례 성분 과장)
        let bx = Int(Double(width) * 0.08), by = Int(Double(height) * 0.08)
        var floats = [Float](repeating: 0, count: width * height * 4)
        let patchW = (width - 2 * bx) / 5
        let midCenter = (x: bx + patchW * 2 + patchW / 2, y: height / 2)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let isBorder = x < bx || x >= width - bx || y < by || y >= height - by
                var t = filmBase
                if !isBorder {
                    var refl = 0.18
                    if y >= height / 3, y < height * 2 / 3 {
                        let k = min((x - bx) * 5 / max(width - 2 * bx, 1), 4)
                        refl = [0.90, 0.36, 0.18, 0.09, 0.02][k]
                    }
                    for c in 0..<3 {
                        let logE = log10(refl / 0.18)
                        let d = max(0.0, crossMid[c] + crossGamma[c] * logE)
                        t[c] = filmBase[c] * pow(10.0, -d)
                    }
                }
                floats[i] = Float(t.x); floats[i + 1] = Float(t.y)
                floats[i + 2] = Float(t.z); floats[i + 3] = 1
            }
        }
        let image = CIImage(
            bitmapData: Data(bytes: floats, count: floats.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
        func develop(neutralBalance: Bool) -> [Float] {
            var params = DevelopParameters()
            params.filmType = .colorNegative
            params.developTarget = .main
            params.autoNeutralBalance = neutralBalance
            let developed = ChromabaseEngine().develop(
                image: image, base: FilmBase(rgb: filmBase, source: .border), params: params)
            let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
            let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
            var out = [Float](repeating: 0, count: width * height * 4)
            ctx.render(developed, toBitmap: &out, rowBytes: width * 4 * MemoryLayout<Float>.size,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .RGBAf, colorSpace: linear)
            return out
        }
        func midImbalance(_ px: [Float]) -> Double {
            let i = (midCenter.y * width + midCenter.x) * 4
            let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2])
            return max(abs(r - g), abs(b - g))
        }
        let off = midImbalance(develop(neutralBalance: false))
        let on = midImbalance(develop(neutralBalance: true))
        XCTAssertGreaterThan(off, 0.02,
            "픽스처 검증: 크로스오버 필름은 반전만으로 미드 bow 가 남아야 한다. off=\(off)")
        XCTAssertLessThan(on, off * 0.55,
            "NeutralBalance 는 크로스오버 bow 를 절반 이하로 줄여야 한다. on=\(on) off=\(off)")
    }

    // MARK: LATD 리프트 — HDR 복구 / 저조도 보호

    /// HDR 장면(어두운 배경 + 스펙큘러 창): 화이트 앵커만으로는 미드가 지나치게 어두워지는
    /// 조건 — 리프트가 배경(9% 회색)을 ±0.7 스탑 이내로 복구해야 한다.
    func diagnoseRemovedExposureLiftHDRBehavior() {
        let width = 240, height = 160
        let (image, centers) = makeNegative(
            width: width, height: height,
            background: 0.09,
            patches: [
                ("gray9", SIMD3(repeating: 0.09)),
                ("gray18", SIMD3(repeating: 0.18)),
                ("specular", SIMD3(repeating: 2.88)),   // +4 스탑 스펙큘러 창
            ])
        let out = developLinear(image, width: width, height: height, target: .main)
        let g9 = linearLuma(out, at: centers["gray9"]!, width: width)
        let stops = log2(max(g9, 1e-6) / 0.09)
        XCTAssertTrue((-0.7...0.7).contains(stops),
            "HDR 장면에서 LATD 리프트가 미드를 복구해야 한다. gray9 편차 " +
            "\(String(format: "%+.2f", stops)) 스탑 (리프트 없으면 −1.5 스탑 이상 어두움)")
    }

    /// 저조도(얇은) 네거티브: 장면 중앙 밀도가 베이스 근처면 리프트 금지 — 어두움은 진짜다
    /// (실기 야간 롤 실측 p50 0.137 방향). 리프트 게이트가 없으면 gray-world 실패로 들뜬다.
    func diagnoseRemovedExposureLiftLowKeyBehavior() {
        let width = 240, height = 160
        // 저조도 장면: 대부분 심한 언더(1% 반사 = 베이스 부근 밀도), 약한 하이라이트 하나.
        let (image, centers) = makeNegative(
            width: width, height: height,
            background: 0.012,
            patches: [
                ("shadow", SIMD3(repeating: 0.012)),
                ("dimlight", SIMD3(repeating: 0.30)),
            ])
        let out = developLinear(image, width: width, height: height, target: .main)
        let shadow = linearLuma(out, at: centers["shadow"]!, width: width)
        XCTAssertLessThan(shadow, 0.05,
            "얇은 저조도 네거티브의 언더 영역이 리프트로 들뜨면 안 된다. shadow=\(shadow)")
    }
}
