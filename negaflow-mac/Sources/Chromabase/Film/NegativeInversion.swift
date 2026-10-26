import Foundation
import CoreImage

// Legacy bounded v4 primitive and explicit scene-range analysis.
// MAIN/PRINT without a scanner profile use NegativeLinearResponse instead.
// Scene sampling is an intentional scanner/recovery-target operation; it changes
// rendering across frames and does not preserve absolute exposure or color.
public enum NegativeInversion {
    static let genericDensityEncodingVersion = "shoulder-print-response-v4"
    /// 스캐너 상대 타겟의 미드톤 설계 피벗. 자동 노출 기준이 아니라 타겟 LUT 좌표다.
    static let midGrayLinear = 0.18

    // MARK: 광도 계약 (자체 설계/판독 상수 — docs/reference/PRINT_RESPONSE.md)

    /// 일반 모델의 직선부 기울기 기준. 필름·공정별 실측 감마를 뜻하지 않는다.
    static let referenceFilmGamma = 0.62
    /// 명목 장면 로그 노출역 — 확산 휘도역(~7⅓스탑 ≈ 2.2 log10) + 딥 하이라이트/광원 여유.
    static let colorSceneLogRange = 2.5
    /// B&W 는 인화지 대비 제약이 없어 관례적으로 더 긴 직선부(짙은 명부까지)를 사용한다.
    static let bwSceneLogRange = 3.5
    /// 일반 모델의 미드그레이 밀도 기준(above-base). 모든 필름의 실측값은 아니다.
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
        /// Legacy v4의 명목 밀도 단위. 고정 응답과 측정 실패 폴백에서 쓴다.
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
    struct ChannelStats: Sendable, Equatable {
        var dmin: SIMD3<Double>       // 필름 베이스 투과율(가장 밝은 = 가장 얇은 밀도)
        var dmaxNorm: SIMD3<Double>   // generic은 RGB 공통, 실측/프리셋만 채널별
        var blackInput: SIMD3<Double> // 장면 어두운 부분(p90 투과율) — 디버그 지표 전용
        var midDensity: Double        // 장면 중앙 밀도(above-base, log10) — LATD 리프트 근거
    }

    /// density-based 네거티브 반전(고정 인화 응답, byte-exact 결정적 primitive).
    /// 장면 히스토그램을 읽지 않으므로 같은 밀도는 프레임 내용과 무관하게 항상 같은 값이 된다
    /// (독립 CPU 참조 = shoulder-print-response-v4). MAIN/PRINT는 NegativeLinearResponse를
    /// 사용한다. `applySceneRanged`의 장면 정규화는 명시적인 스캐너·복구 타깃에만 남긴다.
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

    /// Explicit scene-adaptive inversion for scanner/recovery targets.
    /// Per-channel percentile normalization changes both exposure and color.
    /// The default MAIN/PRINT route does not call this function.
    public static func applySceneRanged(
        to image: CIImage,
        base: FilmBase,
        filmType: FilmType = .colorNegative
    ) -> CIImage {
        var measurements = DevelopSceneMeasurements()
        return applySceneRanged(
            to: image, base: base, filmType: filmType, measurements: &measurements
        )
    }

    /// 이미 잰 장면 측정이 있으면 다시 재지 않는 변형. 없으면 재서 `measurements` 에 채운다.
    /// 측정은 입력 raw·베이스·필름 종류에만 의존하므로, 슬라이더만 움직이는 동안은 그대로
    /// 유효하다(DevelopSceneMeasurements).
    static func applySceneRanged(
        to image: CIImage,
        base: FilmBase,
        filmType: FilmType,
        measurements: inout DevelopSceneMeasurements
    ) -> CIImage {
        let stats = measurements.inversionStats
            ?? sampleStats(image, base: base, filmType: filmType, region: measurements.analysisRegion)
            ?? genericStats(base: base, filmType: filmType)
        measurements.inversionStats = stats
        let inverted = applyDensityEncoding(
            to: image,
            stats: stats,
            response: response(for: filmType)
        )
        return applyMutedSceneVibrance(
            to: inverted,
            monochrome: filmType == .bwNegative,
            region: measurements.analysisRegion,
            amount: &measurements.mutedVibranceAmount
        )
    }

    /// 흐린/평탄 장면(뮤트한 색)의 채도를 살린다. **scene-level 게이트 + per-pixel vibrance**:
    /// 장면 전체 평균 채도가 낮을수록(흐린 풍경) vibrance 를 강하게, 이미 채도 있는 장면은
    /// 0(완전 보호)으로 스케일한다. vibrance 자체도 저채도 픽셀만 올리고 중립은 그대로 두므로
    /// 캐스트를 만들지 않는다. 정상/유채색 장면은 사실상 불변 → 특정 컷 눈속임이 아니라
    /// "뮤트한 장면만 살리는" 일반 규칙이다. 흑백은 chroma 가 없어 무연산.
    static func applyMutedSceneVibrance(to image: CIImage, monochrome: Bool) -> CIImage {
        var amount: Double?
        return applyMutedSceneVibrance(to: image, monochrome: monochrome, amount: &amount)
    }

    static func applyMutedSceneVibrance(
        to image: CIImage,
        monochrome: Bool,
        region: AnalysisRegion? = nil,
        amount cachedAmount: inout Double?
    ) -> CIImage {
        guard !monochrome else { return image }
        // 크로스플랫폼 Vibrance 검증을 위해 이 단계의 입출력을 남긴다.
        dumpProxy(image, name: "preview")

        // linear 채도 기준(실측 캘리브레이션): flat 흐린풍경≈0.037, 흐린/뮤트 풍경≈0.14~0.15,
        // 유채색 장면≈0.36. target 0.24 아래일수록 부스트(흐린 풍경 살림), 유채색(>0.24)은 0으로
        // 완전 보호 → 정상 유채색 컷 불변.
        let amount: Double
        if let cached = cachedAmount {
            amount = cached
        } else {
            let meanSaturation = sceneMeanSaturation(AnalysisRegion.measurementImage(image, region: region))
            amount = min(0.5, max(0.0, (0.24 - meanSaturation) * 3.0))
            if ProcessInfo.processInfo.environment["NEGA_DEBUG"] != nil {
                FileHandle.standardError.write(Data(
                    String(format: "[vib] meanSat=%.4f amount=%.3f\n", meanSaturation, amount).utf8))
            }
        }
        cachedAmount = amount
        guard amount > 0.01 else {
            dumpProxy(image, name: "postvib")
            return image
        }
        let extent = image.extent
        let boosted = image.applyingFilter("CIVibrance", parameters: [
            "inputAmount": amount,
        ]).cropped(to: extent)
        dumpProxy(boosted, name: "postvib")
        return boosted
    }

    /// 320 폭 축소본을 RGBAf 로 덤프한다(NEGA_DUMP_PROXY 전용). sampleStats 의 프록시와 같은
    /// 축소 규칙이라 두 덤프를 화소 단위로 맞대어 볼 수 있다.
    static func dumpProxy(_ image: CIImage, name: String) {
        guard ProcessInfo.processInfo.environment["NEGA_DUMP_PROXY"] != nil,
              let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else { return }
        let extent = image.extent.integral
        guard extent.width > 8, extent.height > 8 else { return }
        let targetW = max(64, min(320, Int(extent.width)))
        let scale = Double(targetW) / Double(extent.width)
        let targetH = max(1, Int(Double(extent.height) * scale))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        var bitmap = [Float](repeating: 0, count: targetW * targetH * 4)
        SamplingContextPool.context(workingColorSpace: linear).render(
            scaled, toBitmap: &bitmap,
            rowBytes: targetW * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: targetW, height: targetH),
            format: .RGBAf, colorSpace: linear
        )
        let data = bitmap.withUnsafeBufferPointer { Data(buffer: $0) }
        try? data.write(to: URL(fileURLWithPath: "/tmp/\(name)-\(targetW)x\(targetH).f32"))
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
        if ProcessInfo.processInfo.environment["NEGA_DUMP_PROXY"] != nil {
            let data = bitmap.withUnsafeBufferPointer { Data(buffer: $0) }
            try? data.write(to: URL(
                fileURLWithPath: "/tmp/satproxy-\(targetW)x\(targetH).f32"
            ))
        }
        var sum = 0.0
        let n = targetW * targetH
        for i in 0..<n {
            let r = Double(bitmap[i * 4]), g = Double(bitmap[i * 4 + 1]), b = Double(bitmap[i * 4 + 2])
            let mx = max(r, max(g, b)), mn = min(r, min(g, b))
            sum += mx > 1e-6 ? (mx - mn) / mx : 0
        }
        return sum / Double(max(n, 1))
    }

    /// Legacy v4 response with fixed stock-relative density units. No frame
    /// normalization or scene vibrance is applied by selecting a stock preset.
    public static func apply(
        to image: CIImage,
        base: FilmBase,
        preset: FilmStockDmin,
        filmType: FilmType = .colorNegative
    ) -> CIImage {
        var measurements = DevelopSceneMeasurements()
        return apply(
            to: image, base: base, preset: preset,
            filmType: filmType, measurements: &measurements
        )
    }

    /// Fixed preset calibration. A stock selection does not authorize scene adaptation.
    static func apply(
        to image: CIImage,
        base: FilmBase,
        preset: FilmStockDmin,
        filmType: FilmType,
        measurements: inout DevelopSceneMeasurements
    ) -> CIImage {
        let stats = measurements.inversionStats
            ?? presetStats(for: image, base: base, preset: preset, filmType: filmType,
                           region: measurements.analysisRegion)
        measurements.inversionStats = stats
        let inverted = applyDensityEncoding(to: image, stats: stats, response: response(for: filmType))
        return inverted
    }

    static func presetStats(for image: CIImage, base: FilmBase,
                            preset: FilmStockDmin,
                            filmType: FilmType = .colorNegative,
                            region: AnalysisRegion? = nil) -> ChannelStats {
        var stats = genericStats(base: base, filmType: filmType)
        guard filmType != .bwNegative else { return stats }
        stats.dmaxNorm *= preset.relativeRangeFactor
        return stats
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
        _ fullImage: CIImage,
        base: FilmBase,
        filmType: FilmType = .colorNegative,
        region: AnalysisRegion? = nil
    ) -> ChannelStats? {
        // 크롭한 사진 영역이 있으면 그 안만 잰다(홀더·백라이트·이웃 프레임 배제).
        let image = AnalysisRegion.measurementImage(fullImage, region: region)
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

        // 검은 프레임 경계(필름 홀더)를 제외하기 위해 내부 6% 인셋만 사용한다. 크롭 영역이면
        // 경계는 이미 잘려 나갔으므로 축소 보간이 크롭 가장자리에서 섞는 두 화소만 버린다 — 6% 를
        // 그대로 두면 사진 가장자리의 실제 명부가 Dmax 측정에서 빠진다.
        let insetX = region == nil ? max(1, Int(Double(targetW) * 0.06)) : 2
        let insetY = region == nil ? max(1, Int(Double(targetH) * 0.06)) : 2
        let innerW = max(1, targetW - 2 * insetX), innerH = max(1, targetH - 2 * insetY)
        var pixels: [SIMD3<Double>] = []
        pixels.reserveCapacity(innerW * innerH)
        for y in insetY..<(insetY + innerH) {
            for x in insetX..<(insetX + innerW) {
                let i = (min(y, targetH - 1) * targetW + min(x, targetW - 1)) * 4
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
        //    불가능해 두지 않는다. 저신호 로그 연산에는 투과율 바닥만 적용한다.
        // 게이팅이 표본을 전멸시키면(베이스가 크게 어긋난 경우) 무게이트로 폴백한다.
        let baseLuma = (base.rgb.x + base.rgb.y + base.rgb.z) / 3
        let gate = baseLuma * 1.12
        let darkCut = baseLuma * 0.15
        let baseRatio = base.rgb.x / max(base.rgb.z, 1e-4)
        let neutralDarkRatioCut: Double? = baseRatio >= 1.5 ? baseRatio * 0.55 : nil
        func isNonFilm(_ p: SIMD3<Double>) -> Bool {
            let luma = (p.x + p.y + p.z) / 3
            if luma > gate { return true }
            if let ratioCut = neutralDarkRatioCut, luma < darkCut,
               p.x / max(p.z, 1e-4) < ratioCut { return true }
            return false
        }
        // 홀더·백라이트 같은 **두께 있는** 비필름 영역의 가장자리 띠(2 화소)도 버린다. 축소 보간이
        // 그 가장자리를 필름과 섞은 화소는 게이트를 통과하면서 최농부(p0.2)를 차지한다. 이 표본은
        // 명시적 장면 분석 타깃의 채널별 범위와 색을 왜곡하므로 측정에서 제외한다.
        // 먼저 3×3 침식으로 흩어진 점을 지운다. 베이스 근처 밝기의 넓은 면에서는 양자화·그레인 수준의
        // 차이로 게이트 판정이 점점이 뒤집히는데, 그 점마다 이웃을 지우면 필름의 91% 가 사라져 남은
        // 화소의 최농부가 입력의 미세한 차이에 크게 흔들렸다(같은 화상의 원본과 화면용 sRGB 사본에서
        // Dmax R 0.146 vs 0.238 → 화면·내보내기 불일치). 혼합 띠는 두께 있는 영역 옆에만 생긴다.
        let nonFilm = pixels.map(isNonFilm)
        var solid = [Bool](repeating: false, count: nonFilm.count)
        for y in 0..<innerH {
            for x in 0..<innerW where nonFilm[y * innerW + x] {
                var allNonFilm = true
                for ny in max(0, y - 1)...min(innerH - 1, y + 1) where allNonFilm {
                    for nx in max(0, x - 1)...min(innerW - 1, x + 1) where !nonFilm[ny * innerW + nx] {
                        allNonFilm = false
                        break
                    }
                }
                solid[y * innerW + x] = allNonFilm
            }
        }
        // 침식된 핵에서 3 화소 = 원래 경계에서 2 화소 띠.
        var nearNonFilm = nonFilm
        if solid.contains(true) {
            let radius = 3
            for y in 0..<innerH {
                for x in 0..<innerW where solid[y * innerW + x] {
                    for ny in max(0, y - radius)...min(innerH - 1, y + radius) {
                        for nx in max(0, x - radius)...min(innerW - 1, x + radius) {
                            nearNonFilm[ny * innerW + nx] = true
                        }
                    }
                }
            }
        }
        var film = pixels.indices.filter { !nearNonFilm[$0] }.map { pixels[$0] }
        if film.count < 64 { film = pixels.indices.filter { !nonFilm[$0] }.map { pixels[$0] } }
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

        // Explicit scene analysis: robust range, without a film-independent density cap.
        let densest = SIMD3(
            max(pct(red, 0.002), 1e-5),
            max(pct(green, 0.002), 1e-5),
            max(pct(blue, 0.002), 1e-5)
        )
        let densestFloor = SIMD3(
            densest.x,
            densest.y,
            densest.z
        )
        // 바닥은 **아무것도 안 찍힌 프레임을 막는 자리**이지 평평한 필름을 부풀리는 자리가
        // 아니다. 0.4 는 바랜 필름의 파랑을 그대로 삼켰다 — 1980~90 년대 카메라 스캔에서
        // 파랑이 정확히 0.40 으로 걸리고(실측 yokohama 진짜 값 0.178), 그만큼 파랑이 과하게
        // 늘어나 사진이 노랗게 나왔다. 실제로 관측한 가장 평평한 채널이 0.13 이므로 그 아래로 둔다.
        let measuredDmax = SIMD3(
            max(0.10, log10(dmin.x / densestFloor.x)),
            max(0.10, log10(dmin.y / densestFloor.y)),
            max(0.10, log10(dmin.z / densestFloor.z))
        )
        let dmaxGeo = pow(measuredDmax.x * measuredDmax.y * measuredDmax.z, 1.0 / 3.0)
        // Windows 포팅본과 축소본 표본을 대조하기 위한 진단(둘 다 opt-in — 평소에는 안 돈다).
        // dmaxNorm 은 이 축소본의 채널별 p0.002 로 정해지므로, 값이 갈리면 최종 픽셀이
        // 채널마다 다르게 움직인다.
        if ProcessInfo.processInfo.environment["NEGA_DEBUG"] != nil {
            FileHandle.standardError.write(Data((
                String(format: "[nega-proxy] targetW=%d targetH=%d inset=(%d,%d) ",
                       targetW, targetH, insetX, insetY)
                + String(format: "pixels=%d film=%d gate=%.6f darkCut=%.6f ",
                         pixels.count, film.count, gate, darkCut)
                + "densest=\(fmt(densest)) densestFloor=\(fmt(densestFloor))"
                + " measuredDmax=\(fmt(measuredDmax))\n"
            ).utf8))
        }
        if ProcessInfo.processInfo.environment["NEGA_DUMP_PROXY"] != nil {
            let data = bitmap.withUnsafeBufferPointer { Data(buffer: $0) }
            try? data.write(to: URL(fileURLWithPath: "/tmp/proxy-\(targetW)x\(targetH).f32"))
        }

        // **잰 값을 쓴다.**
        //
        // 앞 판은 잰 범위가 0.42 아래면 그것을 "측정 실패" 로 보고 nominalRange(1.55, 고대비
        // 가정) 쪽으로 되돌렸다. 그런데 좁은 범위와 실패는 다르다 — 오래되어 바랜 필름은 실제로
        // 평평하다. 측정이 맞는데 틀린 걸로 보고 버리고, 그 고대비 가정이 사진을 검게 눌렀다
        // (실측 yokohama: 잰 범위 0.51 이 1.07 로 되돌려져 현상 평균 0.048/0.113/0.025).
        //
        // 측정이 정말 못 미더운 경우는 값이 작은 것이 아니라 **표본이 없는 것**이고, 그것은
        // 위에서 이미 걸러진다(프록시 실패, 표본 64 개 미만). 남는 위험인 "아무것도 안 찍힌
        // 프레임" 은 위 채널별 바닥이 묶는다.
        //
        // 앞 판의 `shrunkScale * (1 + (measured/geo − 1) * confidence)` 는 confidence 가 1 일 때
        // `measuredDmax[channel]` 과 같은 식이다 — 건강한 스캔은 늘 그 자리였으므로 값이 달라지지 않는다.
        // B&W 는 단일 중립 곡선(세 채널 기하평균) — 채널별로 다르면 중립 회색이 R≠G≠B 로 틀어진다.
        let dmaxNorm: SIMD3<Double> = filmType == .bwNegative
            ? SIMD3(repeating: dmaxGeo)
            : measuredDmax
        let paperBlackInput = SIMD3(pct(red, 0.90), pct(green, 0.90), pct(blue, 0.90)) * 0.97

        // 장면 중앙 밀도(above-base). 채널 median 투과율의 로그 평균(기하평균 밀도) — 디버그 지표.
        let medianT = SIMD3(pct(red, 0.5), pct(green, 0.5), pct(blue, 0.5))
        let midDensity = max(0.0, (
            log10(dmin.x / max(medianT.x, 1e-5)) +
            log10(dmin.y / max(medianT.y, 1e-5)) +
            log10(dmin.z / max(medianT.z, 1e-5))
        ) / 3.0)

        // 장면별 Dmax 정규화 자체가 노출과 색을 바꾼다. 여기서는 미드톤을 추가로 옮기지 않는다.
        // 출력은 legacy v4 응답이 맡으며 미노광 base는 그 응답의 토우에 놓인다.
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
