import Foundation
import CoreImage

// MARK: - NegativeInversion
//
// 계측된 scanner/film characteristic curve가 없을 때의 결정적 기본 경로다.
//
//   D = log10(Dmin / transmission)               // 베이스를 뺀 광학 밀도
//   d = D / dmaxNorm                             // 사용 밀도역 정규화(실측/프리셋/명목)
//   log10(P) = yCeil − amplitude·exp(−(rate·d)^shape)   // 고정 인화 응답(H&D 숄더형)
//
// 인화 응답은 H&D 특성곡선(토우–직선부–숄더)의 숄더 포화 구간을 밀도 도메인에서 직접
// 근사한 단일 해석 곡선이다. 곡선 계수는 저장된 매직 넘버가 아니라 negaflow 광도 계약
// 4앵커(베이스 토우·미드그레이·화이트·천장)에서 닫힌형으로 유도된다(`PrintResponse`,
// docs/reference/PRINT_RESPONSE.md, derivation-lock 테스트). Dmin 정규화와 고정 인화
// 응답만 포함하며 장면 histogram을 읽는 자동 노출/레벨은 아니다.
//
// 설계 이력: 이전 v2는 번들 stock의 최대 Dmax-Dmin(2.23D)을 화면 white처럼 사용한 뒤
// 근거 없는 역특성곡선을 적용해 정상 장면을 좌측에 압축했고, 범위 밖 값을 그대로 내보내
// RGBA8 표시 단계에서 0/255 양끝 포화를 만들었다. 명목 범위는 필름 물성 최대가 아니라
// "정상 노출 장면이 실제 사용하는 밀도역"이어야 한다는 교훈이 광도 계약의 근거다.
//
// 이 generic 경로는 특정 stock 또는 scanner의 색 정확도 주장이 아니다. 장치 정확도에는
// scanner input characterization과 stock/process별 paired reference가 별도로 필요하다.
public enum NegativeInversion {
    static let genericDensityEncodingVersion = "shoulder-print-response-v4"
    /// 스캐너 상대 타겟의 미드톤 설계 피벗. 자동 노출 기준이 아니라 타겟 LUT 좌표다.
    static let midGrayLinear = 0.18

    // MARK: 광도 계약 (자체 설계/판독 상수 — docs/reference/PRINT_RESPONSE.md)

    /// C-41 특성곡선 직선부 기울기 근사(번들 스톡 데이터시트 곡선 판독; 공개 대역 0.55~0.65).
    static let referenceFilmGamma = 0.62
    /// 명목 장면 로그 노출역 — 확산 휘도역(~7⅓스탑 ≈ 2.2 log10) + 딥 하이라이트/광원 여유.
    static let colorSceneLogRange = 2.5
    /// B&W 는 인화지 대비 제약이 없어 관례적으로 더 긴 직선부(짙은 명부까지)를 사용한다.
    static let bwSceneLogRange = 3.5
    /// 정상 노출 장면의 미드그레이 밀도(above-base, 데이터시트 곡선 판독).
    static let normalMidDensity = 0.60
    /// 미드그레이가 앉는 사용 밀도역 내 위치. 장면 기하이므로 필름 타입과 무관하게 공유한다
    /// — 정규화 좌표가 같아야 실측 경로(applySceneRanged)의 노출 앵커가 필름 타입 간 일치한다.
    static var midRangeFraction: Double {
        normalMidDensity / (referenceFilmGamma * colorSceneLogRange)
    }

    /// 고정 인화 응답. log10(P) = yCeil − amplitude·exp(−(rate·d)^shape), d = 정규화 밀도.
    /// 전 구간 단조 증가. 필름 밀도(d≥0)의 출력은 [baseToe, ceiling) 이고 음의 밀도(비필름)는
    /// 토우 아래 유한 양수로 연속 — 0/1 포화가 구조적으로 불가능.
    /// 저장 상수는 앵커 4개뿐이고 곡선 계수는 닫힌형으로 유도된다:
    ///   amplitude = yCeil − log10(baseToe)
    ///   rX        = ln(amplitude / (yCeil − log10(X)))            // X = 미드/화이트 앵커
    ///   shape     = ln(rWhite/rMid) / ln(1/midRangeFraction)
    ///   rate      = rWhite^(1/shape)
    struct PrintResponse: Equatable {
        /// 명목 정규화 밀도 범위. 측정 불가 폴백의 분모이자 flat 장면 수축 목표.
        let normalRange: Double
        /// d=0(필름 베이스) 출력 — 인화 토우. 정확히 0 금지(히스토그램 0 벽 방지).
        let baseToe: Double
        /// d=1(측정 최농부) 출력 — 플랫 마스터 확산 화이트.
        let whiteOutput: Double
        /// d→∞ 점근 상한 — 스펙큘러 헤드룸, 8bit 코드 255 금지.
        let ceiling: Double
        let yCeil: Double
        let amplitude: Double
        let rate: Double
        let shape: Double

        init(normalRange: Double, baseToe: Double, whiteOutput: Double, ceiling: Double) {
            self.normalRange = normalRange
            self.baseToe = baseToe
            self.whiteOutput = whiteOutput
            self.ceiling = ceiling
            yCeil = log10(ceiling)
            amplitude = yCeil - log10(baseToe)
            let rMid = log(amplitude / (yCeil - log10(NegativeInversion.midGrayLinear)))
            let rWhite = log(amplitude / (yCeil - log10(whiteOutput)))
            shape = log(rWhite / rMid) / log(1.0 / NegativeInversion.midRangeFraction)
            rate = pow(rWhite, 1.0 / shape)
        }

        /// 정규화 밀도 → linear 양화. 베이스보다 밝은 비필름 입력(백라이트/퍼포레이션,
        /// 음의 밀도)은 로그 출력 공간에서 토우 점대칭으로 연속시킨다:
        /// y(−|d|) = 2·log10(toe) − y(|d|). 단조가 보존되고 출력은 토우 아래 유한 양수
        /// (하한 ≈ toe²/ceiling)로 수렴한다 — 평탄면/정확히 0 픽셀이 생기지 않는다.
        func linearOutput(normalizedDensity d: Double) -> Double {
            let magnitude = abs(d)
            let y = yCeil - amplitude * exp(-pow(rate * magnitude, shape))
            guard d < 0 else { return pow(10.0, y) }
            let toeY = yCeil - amplitude
            return pow(10.0, 2.0 * toeY - y)
        }

        /// 역함수(합성 픽스처 부호화·라운드트립 검증용). 출력 개구간으로 클램프한다.
        func normalizedDensity(forLinearOutput value: Double) -> Double {
            let bounded = min(max(value, baseToe), ceiling - 1e-9)
            let y = log10(bounded)
            return pow(log(amplitude / (yCeil - y)), 1.0 / shape) / rate
        }
    }

    /// 컬러 응답. 앵커: 베이스→0.001(8bit 코드 3), 미드(사용역 38.7% 지점)→0.18,
    /// 측정 최농부→0.70, 천장 0.90. normalRange = γ(0.62) × 장면 로그역(2.5) = 1.55.
    static let colorResponse = PrintResponse(
        normalRange: referenceFilmGamma * colorSceneLogRange,
        baseToe: 0.001,
        whiteOutput: 0.70,
        ceiling: 0.90
    )
    /// B&W 응답 — 실버 프린트 관례: 컬러보다 깊은 블랙(토우 0.0005)·밝은 명부(0.85/0.98).
    /// normalRange = γ(0.62) × B&W 로그역(3.5) = 2.17.
    static let bwResponse = PrintResponse(
        normalRange: referenceFilmGamma * bwSceneLogRange,
        baseToe: 0.0005,
        whiteOutput: 0.85,
        ceiling: 0.98
    )

    static func response(for filmType: FilmType) -> PrintResponse {
        filmType == .bwNegative ? bwResponse : colorResponse
    }

    /// 명시적 AutoLevels/EXPIRED 레인지 복구의 출력 black floor. 기본 반전에는 적용되지 않는다.
    static let toeFloor = 0.003

    /// 채널별 밀도 통계. dmin/blackInput 은 raw 투과광(0...1 linear) 좌표계 기준.
    struct ChannelStats {
        var dmin: SIMD3<Double>       // 필름 베이스 투과율(가장 밝은 = 가장 얇은 밀도)
        var dmaxNorm: SIMD3<Double>   // generic은 RGB 공통, 실측/프리셋만 채널별
        var blackInput: SIMD3<Double> // 장면 어두운 부분(p90 투과율) — 디버그 지표 전용
        var midDensity: Double        // 장면 중앙 밀도(above-base, log10) — LATD 리프트 근거
    }

    /// density-based 네거티브 반전(고정 인화 응답, byte-exact 결정적 primitive).
    /// 장면 히스토그램을 읽지 않으므로 같은 밀도는 프레임 내용과 무관하게 항상 같은 값이 된다
    /// (독립 CPU 참조 = shoulder-print-response-v4). 실제 현상 파이프라인의 auto 경로는
    /// `applySceneRanged` 로 이 네거티브가 사용한 밀도 범위를 측정해 정규화한다.
    public static func apply(
        to image: CIImage,
        base: FilmBase,
        filmType: FilmType = .colorNegative
    ) -> CIImage {
        applyDensityEncoding(
            to: image,
            stats: genericStats(base: base, filmType: filmType),
            response: response(for: filmType)
        )
    }

    /// auto(프리셋 없음) 현상 경로의 반전. 이 네거티브가 **실제 사용한 per-channel 밀도
    /// 범위(Dmax)** 를 장면 최농부에서 측정해 정규화한다. 고정 명목 범위는 그 범위 근처의
    /// 네거티브(정상 노출)만 올바르게 펴고, 얇은 실스캔(측정 ≈0.85~0.96)은 좁은 대역에
    /// 압축해 어둡고 납작하게(좌측 쏠림+상하 압축) 만든다. 채널별 측정은 압축 제거와 동시에
    /// 필름 염료 기울기 차이를 독립 정규화해 잔여 캐스트/탈채도를 없앤다(= 자동 화이트밸런스).
    /// 미드그레이 정규화 좌표(midRangeFraction)가 고정이므로 노출 앵커는 보존되고,
    /// ScannerTargetGrade 의 photometric 앵커 가정도 유지된다. 측정 불가(극소·저표본 합성
    /// 입력)면 고정 primitive 로 폴백한다.
    public static func applySceneRanged(
        to image: CIImage,
        base: FilmBase,
        filmType: FilmType = .colorNegative
    ) -> CIImage {
        let stats = sampleStats(image, base: base, filmType: filmType)
            ?? genericStats(base: base, filmType: filmType)
        let inverted = applyDensityEncoding(
            to: image,
            stats: stats,
            response: response(for: filmType)
        )
        return applyMutedSceneVibrance(to: inverted, monochrome: filmType == .bwNegative)
    }

    /// 흐린/평탄 장면(뮤트한 색)의 채도를 살린다. **scene-level 게이트 + per-pixel vibrance**:
    /// 장면 전체 평균 채도가 낮을수록(흐린 풍경) vibrance 를 강하게, 이미 채도 있는 장면은
    /// 0(완전 보호)으로 스케일한다. vibrance 자체도 저채도 픽셀만 올리고 중립은 그대로 두므로
    /// 캐스트를 만들지 않는다. 정상/유채색 장면은 사실상 불변 → 특정 컷 눈속임이 아니라
    /// "뮤트한 장면만 살리는" 일반 규칙이다. 흑백은 chroma 가 없어 무연산.
    static func applyMutedSceneVibrance(to image: CIImage, monochrome: Bool) -> CIImage {
        guard !monochrome else { return image }
        let meanSaturation = sceneMeanSaturation(image)
        // linear 채도 기준(실측 캘리브레이션): flat 흐린풍경≈0.037, 흐린/뮤트 풍경≈0.14~0.15,
        // 유채색 장면≈0.36. target 0.24 아래일수록 부스트(흐린 풍경 살림), 유채색(>0.24)은 0으로
        // 완전 보호 → 정상 유채색 컷 불변.
        let amount = min(0.5, max(0.0, (0.24 - meanSaturation) * 3.0))
        if ProcessInfo.processInfo.environment["NEGA_DEBUG"] != nil {
            FileHandle.standardError.write(Data(
                String(format: "[vib] meanSat=%.4f amount=%.3f\n", meanSaturation, amount).utf8))
        }
        guard amount > 0.01 else { return image }
        let extent = image.extent
        return image.applyingFilter("CIVibrance", parameters: [
            "inputAmount": amount,
        ]).cropped(to: extent)
    }

    /// 작은 프록시를 linear 작업공간 그대로 렌더해 장면 평균 채도(HSV S = (max−min)/max)를 잰다.
    /// 입력이 linear 이므로 색공간 불일치 없이 실제 인버전 출력 값에서 측정한다(임계는 linear
    /// 채도 기준으로 캘리브레이션).
    static func sceneMeanSaturation(_ image: CIImage) -> Double {
        let extent = image.extent.integral
        guard extent.width > 4, extent.height > 4,
              let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else { return 0.5 }
        let targetW = max(32, min(160, Int(extent.width)))
        let scale = Double(targetW) / Double(extent.width)
        let targetH = max(1, Int(Double(extent.height) * scale))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        var bitmap = [Float](repeating: 0, count: targetW * targetH * 4)
        SamplingContextPool.context(workingColorSpace: linear).render(
            scaled, toBitmap: &bitmap,
            rowBytes: targetW * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: targetW, height: targetH),
            format: .RGBAf, colorSpace: linear
        )
        var sum = 0.0
        let n = targetW * targetH
        for i in 0..<n {
            let r = Double(bitmap[i * 4]), g = Double(bitmap[i * 4 + 1]), b = Double(bitmap[i * 4 + 2])
            let mx = max(r, max(g, b)), mn = min(r, min(g, b))
            sum += mx > 1e-6 ? (mx - mn) / mx : 0
        }
        return sum / Double(max(n, 1))
    }

    /// 필름 Dmin/Dmax 프리셋을 적용한 반전. 프리셋의 역할(측정 base 우선 원칙):
    ///   • dmin(베이스 투과율) — 호출측이 실측/프리셋으로 세팅해 전달.
    ///   • dmaxNorm 채널 **비율**(필름 물성 = 염료 분리) — 장면 히스토그램의 채널별 왜곡
    ///     (파란 하늘이 B dmaxNorm 을 폭발시키는 보라 hue shift)을 회피한다.
    /// 전체 스케일도 프리셋의 공개 특성곡선 판독값을 그대로 쓴다. 장면 percentile로 다시
    /// 늘리거나 줄이면 프레임 내용에 따라 같은 필름의 노출과 색 좌표가 바뀌기 때문이다.
    public static func apply(
        to image: CIImage,
        base: FilmBase,
        preset: FilmStockDmin,
        filmType: FilmType = .colorNegative
    ) -> CIImage {
        let stats = presetStats(for: image, base: base, preset: preset, filmType: filmType)
        return applyDensityEncoding(to: image, stats: stats, response: response(for: filmType))
    }

    static func presetStats(for image: CIImage, base: FilmBase,
                            preset: FilmStockDmin,
                            filmType: FilmType = .colorNegative) -> ChannelStats {
        let dmin = clampedDmin(base.rgb)
        // 스케일(노출역)은 **실측**한다. 고정 preset.dmaxNorm(데이터시트 밀도역 ~2.0D)로 정규화하면
        // 얇은 실스캔(실제 사용역 ~0.85~1.5D)이 좁은 대역에 압축돼 어둡고 납작해진다(좌측 쏠림+상하
        // 압축) — auto 경로(applySceneRanged)가 이미 실측으로 해결한 문제를 프리셋만 재현하던 버그.
        // 채널 **비율**(염료 분리 = 필름 물성)은 프리셋을 앵커로 써 장면 의존 채널 왜곡(파란 하늘의
        // 보라 shift)을 피한다 → 노출은 보존하면서 필름별 색 특성만 반영한다.
        let measured = sampleStats(image, base: base, filmType: filmType)
        let sceneScale = measured.map {
            pow($0.dmaxNorm.x * $0.dmaxNorm.y * $0.dmaxNorm.z, 1.0 / 3.0)
        } ?? response(for: filmType).normalRange
        if filmType == .bwNegative {
            return ChannelStats(dmin: dmin, dmaxNorm: SIMD3(repeating: sceneScale),
                                blackInput: dmin, midDensity: 0)
        }
        let p = preset.dmaxNorm
        let pGeo = pow(max(p.x, 1e-4) * max(p.y, 1e-4) * max(p.z, 1e-4), 1.0 / 3.0)
        let dmaxNorm = SIMD3(sceneScale * p.x / pGeo,
                             sceneScale * p.y / pGeo,
                             sceneScale * p.z / pGeo)
        return ChannelStats(dmin: dmin, dmaxNorm: dmaxNorm, blackInput: dmin, midDensity: 0)
    }

    static func genericStats(
        base: FilmBase,
        filmType: FilmType = .colorNegative
    ) -> ChannelStats {
        let dmin = clampedDmin(base.rgb)
        return ChannelStats(
            dmin: dmin,
            dmaxNorm: SIMD3(repeating: response(for: filmType).normalRange),
            blackInput: dmin,
            midDensity: 0
        )
    }

    private static func clampedDmin(_ value: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            min(max(value.x, 1e-3), 1.0),
            min(max(value.y, 1e-3), 1.0),
            min(max(value.z, 1e-3), 1.0)
        )
    }

    // MARK: 채널별 통계 샘플링

    static func sampleStats(
        _ image: CIImage,
        base: FilmBase,
        filmType: FilmType = .colorNegative
    ) -> ChannelStats? {
        let extent = image.extent.integral
        guard extent.width > 8, extent.height > 8,
              let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }

        // 작은 축소본을 linear 영역에서 렌더해 채널별 히스토그램을 만든다.
        let targetW = max(64, min(320, Int(extent.width)))
        let scale = Double(targetW) / Double(extent.width)
        let targetH = max(1, Int(Double(extent.height) * scale))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))

        var bitmap = [Float](repeating: 0, count: targetW * targetH * 4)
        SamplingContextPool.context(workingColorSpace: linear).render(
            scaled,
            toBitmap: &bitmap,
            rowBytes: targetW * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: targetW, height: targetH),
            format: .RGBAf,
            colorSpace: linear
        )

        // 검은 프레임 경계(필름 홀더)를 제외하기 위해 내부 6% 인셋만 사용한다.
        let insetX = max(1, Int(Double(targetW) * 0.06))
        let insetY = max(1, Int(Double(targetH) * 0.06))
        var pixels: [SIMD3<Double>] = []
        pixels.reserveCapacity(targetW * targetH)
        for y in insetY..<max(insetY + 1, targetH - insetY) {
            for x in insetX..<max(insetX + 1, targetW - insetX) {
                let i = (y * targetW + x) * 4
                pixels.append(SIMD3(
                    Double(bitmap[i]), Double(bitmap[i + 1]), Double(bitmap[i + 2])
                ))
            }
        }
        // 비필름 게이팅:
        //  • 밝은 쪽 — 네거티브에서 베이스보다 뚜렷이 밝은 픽셀은 필름일 수 없다(백라이트/
        //    퍼포레이션/무필름 여백). 이걸 percentile 에 섞으면 sampledDmin(p99.8)이 백라이트로
        //    승격돼 **올바른 base 마저 무시**되고(auto/preset), blackInput(p90)도 광원에 끌려가
        //    가져온 멀티 스트립 스캔이 물빠진 렌더링이 된다. 게이트는 base 추정 오차(±10% 내외)
        //    를 견뎌야 한다 — 1.06 은 base 가 몇 % 만 어둡게 추정돼도 베이스 근처의 진짜 필름
        //    최암부(미노광 섀도)를 잘라 dmin 을 크게 밑돌게 했다(흑백 합성 실측). 백라이트/
        //    퍼포레이션은 통상 base 대비 +30% 이상이므로 1.12 도 여전히 배제한다.
        //  • 어두운 쪽 — 스트립 사이 검정 갭 같은 비필름 어두움은 densest(p0.2)를 오염시켜
        //    dmaxNorm 을 왜곡한다. 컬러 네거티브 필름 픽셀은 깊은 암부에서도 베이스의 채널
        //    로그비(오렌지)를 대체로 유지하므로, 깊은 어두움(< 베이스 휘도의 15%)이면서 R/B
        //    비가 베이스의 55% 미만(중립에 가까움)인 픽셀은 필름이 아니다. B&W 는 이 판별이
        //    불가능해 두지 않는다(단일 곡선이라 색 캐스트가 없고 densestFloor 가 완충).
        // 게이팅이 표본을 전멸시키면(베이스가 크게 어긋난 경우) 무게이트로 폴백한다.
        let baseLuma = (base.rgb.x + base.rgb.y + base.rgb.z) / 3
        let gate = baseLuma * 1.12
        let darkCut = baseLuma * 0.15
        let baseRatio = base.rgb.x / max(base.rgb.z, 1e-4)
        let neutralDarkRatioCut: Double? = baseRatio >= 1.5 ? baseRatio * 0.55 : nil
        var film = pixels.filter { p in
            let luma = (p.x + p.y + p.z) / 3
            if luma > gate { return false }
            if let ratioCut = neutralDarkRatioCut, luma < darkCut,
               p.x / max(p.z, 1e-4) < ratioCut { return false }
            return true
        }
        if film.count < 64 { film = pixels }
        guard film.count >= 64 else { return nil }
        var red = film.map(\.x), green = film.map(\.y), blue = film.map(\.z)
        red.sort(); green.sort(); blue.sort()

        func pct(_ s: [Double], _ f: Double) -> Double {
            let idx = max(0, min(s.count - 1, Int(Double(s.count - 1) * f)))
            return s[idx]
        }

        // Dmin은 앞 단계에서 측정·선택된 필름 베이스의 절대 투과율이다. source는 provenance일
        // 뿐 같은 RGB 측정값의 수학적 의미를 바꾸지 않는다. 장면 p99.8과 다시 혼합하면 장면
        // 색/구도가 Dmin을 이동시켜 동일한 측정값도 auto/manual 여부에 따라 전 프레임 색과
        // 노출이 달라진다. 측정 신뢰도 판단과 폴백은 FilmBaseEstimator/resolveFilmBase가 맡는다.
        let dmin = clampedDmin(base.rgb)
        let nominalRange = response(for: filmType).normalRange

        // Dmax = 이 네거티브가 **실제로 사용한** per-channel 밀도 범위. 장면 최농부(p0.2
        // 투과율 — 절대 최소가 아닌 강건 percentile 로 dust/스펙큘러 배제)로 측정한다.
        // densest 에 물성 하한(1.8D)을 둬 극단
        // 단색 장면(파란 하늘이 B 최농부만 비정상적으로 낮춰 dmax_B 를 폭발시키는 보라 shift)을
        // 막고, 0.4 하한으로 저신호 폭주를 막는다. 채널별 dmax 가 필름 염료 기울기 차이를 독립
        // 정규화(= 자동 화이트밸런스)하며, 정규화 밀도(density/dmax)가 [0,1] 전 범위를 채워
        // 고정 dmax 가 만든 압축을 제거한다.
        let densest = SIMD3(
            max(pct(red, 0.002), 1e-5),
            max(pct(green, 0.002), 1e-5),
            max(pct(blue, 0.002), 1e-5)
        )
        let densestFloor = SIMD3(
            max(densest.x, dmin.x * pow(10.0, -1.8)),
            max(densest.y, dmin.y * pow(10.0, -1.8)),
            max(densest.z, dmin.z * pow(10.0, -1.8))
        )
        let measuredDmax = SIMD3(
            max(0.4, log10(dmin.x / densestFloor.x)),
            max(0.4, log10(dmin.y / densestFloor.y)),
            max(0.4, log10(dmin.z / densestFloor.z))
        )
        let dmaxGeo = pow(measuredDmax.x * measuredDmax.y * measuredDmax.z, 1.0 / 3.0)

        // 저DR(평탄/흐린 날) 신뢰도 shrinkage. 측정 Dmax 기하평균이 필름 물성 범위보다 크게
        // 낮으면 장면이 필름 밀도 범위를 거의 안 쓴 것(평탄/흐린 날)이고, per-channel 측정이
        // 소표본·노이즈로 불안정해 (1) 좁은 대역을 풀레인지로 과다 스트레치(과다 밝기), (2)
        // 채널별 skew 로 캐스트(빨강)를 만든다. 신뢰도 w(측정 기하평균 기반 smoothstep)로 스케일은
        // nominal(고정 인화 응답)로, 채널 비는 중립(1)로 수축해 안전한 photometric 폴백으로 간다.
        // 정상 DR 장면(w≈1)은 완전 측정값을 유지하므로 작업 scan 결과는 불변이다.
        let drT = min(1.0, max(0.0, (dmaxGeo - 0.42) / (0.62 - 0.42)))
        let drConfidence = drT * drT * (3.0 - 2.0 * drT)
        let shrunkScale = nominalRange + (dmaxGeo - nominalRange) * drConfidence
        func shrunkChannel(_ measured: Double) -> Double {
            shrunkScale * (1.0 + (measured / dmaxGeo - 1.0) * drConfidence)
        }
        // B&W 는 단일 중립 곡선(세 채널 기하평균) — 채널별로 다르면 중립 회색이 R≠G≠B 로 틀어진다.
        let dmaxNorm: SIMD3<Double> = filmType == .bwNegative
            ? SIMD3(repeating: shrunkScale)
            : SIMD3(shrunkChannel(measuredDmax.x),
                    shrunkChannel(measuredDmax.y),
                    shrunkChannel(measuredDmax.z))
        let paperBlackInput = SIMD3(pct(red, 0.90), pct(green, 0.90), pct(blue, 0.90)) * 0.97

        // 장면 중앙 밀도(above-base). 채널 median 투과율의 로그 평균(기하평균 밀도) — 디버그 지표.
        let medianT = SIMD3(pct(red, 0.5), pct(green, 0.5), pct(blue, 0.5))
        let midDensity = max(0.0, (
            log10(dmin.x / max(medianT.x, 1e-5)) +
            log10(dmin.y / max(medianT.y, 1e-5)) +
            log10(dmin.z / max(medianT.z, 1e-5))
        ) / 3.0)
        _ = dmaxGeo

        // 노출(미드) 자동 리프트는 여기서 하지 않는다 — opt-in AutoTone(LATD)의 몫이다.
        // 실측 Dmax 는 범위·WB 만 되살리고 노출은 고정 인화 응답이 맡는다. 여기서 미드를
        // 강제로 옮기면 (1) 밝은/어두운 장면을 회색으로 끌어당기는 gray-world 오류, (2)
        // base 가 토우 아래로 밀려 히스토그램 양끝 폭발(베이스=정확히 0)이 재발한다.
        // 고정 응답은 base 를 구조적으로 토우(baseToe)에 앉힌다.
        let stats = ChannelStats(dmin: dmin, dmaxNorm: dmaxNorm,
                                 blackInput: paperBlackInput, midDensity: midDensity)
        if ProcessInfo.processInfo.environment["NEGA_DEBUG"] != nil {
            FileHandle.standardError.write(Data((
                "[nega] dmin=\(fmt(dmin)) dmaxNorm=\(fmt(dmaxNorm)) blackIn=\(fmt(paperBlackInput))"
                + String(format: " midD=%.3f\n", midDensity)
            ).utf8))
        }
        return stats
    }

    private static func fmt(_ v: SIMD3<Double>) -> String {
        String(format: "(%.4f,%.4f,%.4f)", v.x, v.y, v.z)
    }

    static func fallbackStats(
        base: FilmBase,
        filmType: FilmType = .colorNegative
    ) -> ChannelStats {
        genericStats(base: base, filmType: filmType)
    }

    // MARK: 상대 밀도 + 고정 인화 응답

    /// CPU 참조 구현 — Metal `negativeInvert`와 같은 수식.
    static func positiveValue(transmission t: Double,
                              dmin: Double,
                              dmaxNorm: Double,
                              filmType: FilmType = .colorNegative) -> Double {
        let clamped = max(t, 1e-5)
        let density = log10(dmin / clamped)
        return response(for: filmType)
            .linearOutput(normalizedDensity: density / max(dmaxNorm, 1e-6))
    }

    static func applyDensityEncoding(
        to image: CIImage,
        stats: ChannelStats,
        response: PrintResponse = NegativeInversion.colorResponse
    ) -> CIImage {
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "negativeInvert") else {
            return image
        }
        let extent = image.extent
        return kernel.apply(extent: extent, arguments: [
            image,
            CIVector(x: CGFloat(stats.dmin.x), y: CGFloat(stats.dmin.y),
                     z: CGFloat(stats.dmin.z), w: 0),
            CIVector(x: CGFloat(stats.dmaxNorm.x), y: CGFloat(stats.dmaxNorm.y),
                     z: CGFloat(stats.dmaxNorm.z), w: 0),
            CIVector(x: CGFloat(response.yCeil), y: CGFloat(response.amplitude),
                     z: CGFloat(response.rate), w: CGFloat(response.shape)),
        ])?.cropped(to: extent) ?? image
    }
}
