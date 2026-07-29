import Foundation
import CoreImage
import CoreGraphics

extension ChromabaseEngine {
    func applyNegativeFilmPipeline(
        to input: CIImage,
        base: FilmBase?,
        params: DevelopParameters,
        sampleColorSpace: CGColorSpace,
        extent: CGRect
    ) -> CIImage {
        var img = input
        let preset: FilmStockDmin? = (params.baseEstimationMode == .preset)
            ? params.filmStockDminID.flatMap { FilmStockDminRegistry.find($0) } : nil
        let fb = resolveFilmBase(for: img, provided: base, preset: preset, params: params)
        if let preset {
            img = NegativeInversion.apply(
                to: img, base: fb, preset: preset, filmType: params.filmType
            )
        } else {
            // auto 경로: 이 네거티브가 실제 사용한 per-channel 밀도 범위를 측정해 정규화한다
            // (고정 dmax 는 얇은 실스캔을 압축·어둡게·탈색·캐스트로 만든다). 노출은 보존된다.
            img = NegativeInversion.applySceneRanged(to: img, base: fb, filmType: params.filmType)
        }
        // 장면 적응(자동) 보정은 opt-in — 명시적으로 켰을 때만 실행한다.
        // 반전(밀도 정규화)은 결정적이므로 색이 base/프리셋만으로 예측 가능해진다.
        // 측정 도메인은 **입력 태그와 무관하게 linear** — 반전 후 작업공간 값은 항상
        // linear 이고 보정(CIColorMatrix 스트레치/linear cube 감마)도 linear 값에 적용된다.
        // 과거처럼 입력 태그 유래 sampleColorSpace(sRGB 태그 가져오기 → sRGB)로 percentile/
        // median 을 재면 측정과 적용 도메인이 어긋나 섀도 크러시(블랙포인트가 sRGB 값으로
        // 측정돼 linear 에서 과대 감산)·감마 과보정(≈2.2×)이 생긴다.
        let measureSpace = CGColorSpace(name: CGColorSpace.linearSRGB) ?? sampleColorSpace
        if params.autoLevels {
            // outputBlack: 반전 토우 플로어(paper black) 보존 — 0 이면 p0.5 블랙포인트가
            // 최암부 빈 0 벽을 다시 만든다(히스토그램 양끝 폭발의 재발 경로).
            img = AutoLevels.apply(to: img, sampleColorSpace: measureSpace,
                                   outputWhite: 0.95,
                                   outputBlack: NegativeInversion.toeFloor)
        }
        if params.autoNeutralBalance {
            img = NeutralBalance.apply(to: img, sampleColorSpace: measureSpace)
        }
        // 타겟별 베이스 분기:
        //   main/print          — Dmin + 고정 인화 응답으로 만든 중립 기본 양화. 장면별 자동
        //                         스트레치나 타겟 룩(채도 감쇠/커브/샤픈)은 굽지 않는다.
        //   NORITSU HS-1800 /
        //   FUJI SP-3000        — 독자 베이스(실기 실측 프로파일 기반 ScannerTargetGrade).
        //                         main 룩을 섞지 않는다. 수동 프로파일 얹기(ScannerProfileGrade)도
        //                         ScannerTargetGrade 가 흡수하므로 중복 적용하지 않는다.
        //   RESCUE              — 열화(유통기한/방사선 포그) 필름 복구 베이스(RescueGrade).
        //                         반전이 흡수 못 하는 채널별 계조 압축·크로스오버 캐스트·컨페티
        //                         노이즈를 scene-측정으로 보정한다.
        if params.developTarget.isScannerEmulation {
            img = ScannerTargetGrade.apply(to: img, target: params.developTarget, params: params)
        }
        if params.developTarget == .rescue {
            // EXPIRED 자체는 엔드포인트 스트레치/고정 커브/NR을 소유하지 않는다. 여러 휘도대와
            // 공간에서 holdout까지 통과한 중립축 증거가 있을 때만 bounded 상대 보정을 적용한다.
            img = RescueGrade.apply(to: img, sampleColorSpace: measureSpace,
                                    filmType: params.filmType,
                                    recoverRange: false)
        }
        // 타겟 프로파일 밖의 고정 NR·별도 명부 탈채도·추가 gamut 압축은 적용하지 않는다.
        // 현재 스캐너 자료에는 해당 공간 필터의 반경/강도나 고정 desaturation을 보정할
        // paired reference가 없고, EXPIRED도 열화 유형별 측정 없이는 고정 탈채도가 성립하지
        // 않는다. 사용자 NR은 PostPipeline의 명시적 opt-in 단계에서만 수행한다.
        if !params.developTarget.isScannerEmulation,
           params.developTarget != .rescue,
           let profile = scannerProfile(for: params) {
            img = ScannerProfileGrade.apply(to: img, profile: profile)
        }
        img = ColorModel.apply(to: img, params: params)
        img = ToneMapper.applyExposure(to: img, stops: params.exposure)
        img = ToneMapper.applyToneCurves(to: img, params: params)
        return img
    }

    /// 네거티브 파이프라인의 FilmBase 결정. 우선순위:
    ///   1. Manual — 사용자가 명시한 base(절대 Dmin 의미론).
    ///   2. Preset — **실측 우선**(측정 base 우선 원칙): 제공된/추정된 실측 base 가 Dmin 앵커,
    ///      프리셋은 dmaxNorm(필름 물성)만 담당. 실측 불가 시에만 프리셋 Dmin × 광원 트림 폴백.
    ///   3. Auto — 실측 추정, 실패 시 장면 가장자리 폴백.
    func resolveFilmBase(
        for image: CIImage,
        provided base: FilmBase?,
        preset: FilmStockDmin?,
        params: DevelopParameters
    ) -> FilmBase {
        let neutralBase = params.filmType == .bwNegative
        if let manual = params.manualBaseRGB, params.baseEstimationMode == .manual {
            return FilmBase(rgb: manual, source: .manual)
        }
        if let preset {
            // provided base(앱이 estimateFilmBase 로 계산)는 이미 광원 게인이 적용돼 있다 → 그대로 사용
            // (재적용 금지 = 이중 적용 방지). provided 가 없을 때만(드묾) 여기서 fresh 측정+게인 적용.
            if let provided = base { return provided }
            let resolved: FilmBase = Self.estimateBaseWithChromogenicFallback(
                from: image, neutralBase: neutralBase, confidentOnly: true)
                ?? FilmBase(rgb: preset.dminTransmission, source: .manual)
            return Self.applyLightSourceGain(to: resolved,
                                             lightSourceProfileID: params.lightSourceProfileID,
                                             neutralBase: neutralBase)
        }
        if let provided = base
            ?? Self.estimateBaseWithChromogenicFallback(from: image, neutralBase: neutralBase) {
            return provided
        }
        return estimateFallbackBaseFromScene(image, neutralBase: neutralBase)
    }

    func negativeDebugMetrics(
        for image: CIImage,
        base: FilmBase,
        preset: FilmStockDmin?,
        filmType: FilmType
    ) -> DevelopDebugMetrics {
        let stats: NegativeInversion.ChannelStats
        if let preset {
            stats = NegativeInversion.presetStats(
                for: image, base: base, preset: preset, filmType: filmType
            )
        } else {
            stats = NegativeInversion.sampleStats(image, base: base, filmType: filmType)
                ?? NegativeInversion.fallbackStats(base: base, filmType: filmType)
        }
        return DevelopDebugMetrics(
            baseRGB: base.rgb,
            dmin: stats.dmin,
            dmaxNorm: stats.dmaxNorm,
            blackInput: stats.blackInput
        )
    }

    func gamutSoftClip(_ image: CIImage) -> CIImage {
        let extent = image.extent
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "gamutSoftClip") else { return image }
        return kernel.apply(extent: extent, arguments: [image])?.cropped(to: extent) ?? image
    }

    func applyHighlightDesaturation(to image: CIImage,
                                    strength: Double = 0.7,
                                    startY: Double = 0.70) -> CIImage {
        let extent = image.extent
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "highlightDesaturate") else { return image }
        return kernel.apply(extent: extent, arguments: [image, Float(strength), Float(startY)])?
            .cropped(to: extent) ?? image
    }

    func scannerProfile(for params: DevelopParameters) -> ScannerProfile? {
        guard let id = params.scannerProfileID else { return nil }
        return ScannerProfileRegistry.load(named: id)
    }

    func estimateFallbackBaseFromScene(_ image: CIImage, neutralBase: Bool = false) -> FilmBase {
        // 폴백 상수: 오렌지 마스크(컬러) / 중립 회색(B&W). 과거엔 B&W 도 오렌지 폴백으로
        // 떨어져 반전 캐스트를 만들었다.
        let fallbackRGB: SIMD3<Double> = neutralBase
            ? SIMD3(0.80, 0.80, 0.80)
            : SIMD3(0.86, 0.68, 0.50)
        guard let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else {
            return FilmBase(rgb: fallbackRGB, source: .auto)
        }
        let extent = image.extent
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
        let edgeFrac = 0.06
        let ex = max(1, Int(Double(targetW) * edgeFrac))
        let ey = max(1, Int(Double(targetH) * edgeFrac))
        var edgePixels: [SIMD3<Double>] = []
        for y in 0..<targetH {
            for x in 0..<targetW {
                let isEdge = x < ex || x >= targetW - ex || y < ey || y >= targetH - ey
                guard isEdge else { continue }
                let i = (y * targetW + x) * 4
                edgePixels.append(SIMD3(
                    Double(bitmap[i]), Double(bitmap[i + 1]), Double(bitmap[i + 2])
                ))
            }
        }
        // 어두운 쪽 컷은 이 스캔의 가장자리에서 실제로 나온 밝은 값 기준이다. 고정 컷(옛 0.30)은
        // 선형 raw 처럼 값이 낮게 실린 스캔에서 표본을 전멸시키고 상수 폴백으로 떨어뜨렸다.
        let edgeLumas = edgePixels.map { ($0.x + $0.y + $0.z) / 3 }.filter { $0 < 0.92 }.sorted()
        guard !edgeLumas.isEmpty else { return FilmBase(rgb: fallbackRGB, source: .auto) }
        let edgePeak = edgeLumas[Int(0.99 * Double(edgeLumas.count - 1))]
        let lumaFloor = max(0.02, edgePeak * 0.45)
        var rVals: [Double] = [], gVals: [Double] = [], bVals: [Double] = []
        for pixel in edgePixels {
            let (r, g, b) = (pixel.x, pixel.y, pixel.z)
            let luma = (r + g + b) / 3
            guard luma >= lumaFloor, luma < 0.92 else { continue }
            let peak = max(r, max(g, b))
            if neutralBase {
                let tolerance = FilmBaseEstimator.maximumNeutralSpreadRatio * peak
                    + FilmBaseEstimator.neutralSpreadFloor
                guard abs(r - g) <= tolerance, abs(g - b) <= tolerance else { continue }
            } else {
                guard r >= g - 0.01, g >= b - 0.01,
                      (r - b) >= max(0.003, 0.10 * peak) else { continue }
            }
            rVals.append(r); gVals.append(g); bVals.append(b)
        }
        guard rVals.count >= 32 else {
            return FilmBase(rgb: fallbackRGB, source: .auto)
        }
        func pct(_ a: [Double], _ p: Double) -> Double {
            let s = a.sorted(); let idx = Int(p * Double(s.count - 1)); return s[idx]
        }
        return FilmBase(rgb: SIMD3(pct(rVals, 0.90), pct(gVals, 0.90), pct(bVals, 0.90)), source: .auto)
    }

}
