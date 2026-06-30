import CoreImage

enum ChromabaseMetalKernels {
    static func colorKernel(named name: String) -> CIColorKernel? {
        kernels[name] as? CIColorKernel
    }

    static var availableKernelNames: Set<String> {
        Set(kernels.keys)
    }

    private static let kernels: [String: CIKernel] = {
        do {
            return Dictionary(
                uniqueKeysWithValues: try CIKernel.kernels(withMetalString: source).map { ($0.name, $0) }
            )
        } catch {
            assertionFailure("Failed to compile Chromabase Metal kernels: \(error)")
            return [:]
        }
    }()

    private static let source = """
    #include <CoreImage/CoreImage.h>
    using namespace metal;

    // ── HSL 헬퍼 (Color Mixer / Calibration 공용) ──
    inline float3 rgb2hsl(float3 c) {
        float maxc = max(c.r, max(c.g, c.b));
        float minc = min(c.r, min(c.g, c.b));
        float l = (maxc + minc) * 0.5;
        float h = 0.0, s = 0.0;
        float d = maxc - minc;
        if (d > 1e-5) {
            s = l > 0.5 ? d / (2.0 - maxc - minc) : d / (maxc + minc);
            if (maxc == c.r)      h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
            else if (maxc == c.g) h = (c.b - c.r) / d + 2.0;
            else                  h = (c.r - c.g) / d + 4.0;
            h /= 6.0;
        }
        return float3(h, s, l);
    }
    inline float hue2rgb(float p, float q, float t) {
        if (t < 0.0) t += 1.0;
        if (t > 1.0) t -= 1.0;
        if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
        if (t < 1.0 / 2.0) return q;
        if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
        return p;
    }
    inline float3 hsl2rgb(float3 hsl) {
        float h = hsl.x, s = hsl.y, l = hsl.z;
        if (s < 1e-5) return float3(l);
        float q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
        float p = 2.0 * l - q;
        return float3(hue2rgb(p, q, h + 1.0 / 3.0), hue2rgb(p, q, h), hue2rgb(p, q, h - 1.0 / 3.0));
    }

    // Color Mixer (HSL) — 8색 각각 hue/sat/lum. hueA/B = 빨강~자홍 8밴드를 float4 2개로 묶음.
    [[stitchable]] float4 colorMixerHSL(
        coreimage::sample_t src,
        float4 hueA, float4 hueB, float4 satA, float4 satB, float4 lumA, float4 lumB
    ) {
        float3 hsl = rgb2hsl(clamp(src.rgb, 0.0, 1.0));
        float centers[8] = {0.0, 0.083333, 0.166667, 0.333333, 0.5, 0.666667, 0.75, 0.833333};
        float hueAdj[8] = {hueA.x, hueA.y, hueA.z, hueA.w, hueB.x, hueB.y, hueB.z, hueB.w};
        float satAdj[8] = {satA.x, satA.y, satA.z, satA.w, satB.x, satB.y, satB.z, satB.w};
        float lumAdj[8] = {lumA.x, lumA.y, lumA.z, lumA.w, lumB.x, lumB.y, lumB.z, lumB.w};
        float bw = 0.14;
        float wsum = 0.0, hueShift = 0.0, satF = 0.0, lumF = 0.0;
        for (int i = 0; i < 8; i++) {
            float dd = abs(hsl.x - centers[i]);
            dd = min(dd, 1.0 - dd);
            float w = max(0.0, 1.0 - dd / bw);
            wsum += w; hueShift += w * hueAdj[i]; satF += w * satAdj[i]; lumF += w * lumAdj[i];
        }
        if (wsum > 1e-4) { hueShift /= wsum; satF /= wsum; lumF /= wsum; }
        float gate = smoothstep(0.04, 0.18, hsl.y);   // 무채색(회색)은 hue 미정 → 보호
        hsl.x = fract(hsl.x + hueShift * 0.0833 * gate + 1.0);  // ±30°
        hsl.y = clamp(hsl.y * (1.0 + satF * gate), 0.0, 1.0);
        hsl.z = clamp(hsl.z + lumF * 0.16 * gate, 0.0, 1.0);
        return float4(clamp(hsl2rgb(hsl), 0.0, 1.0), src.a);
    }

    // Color Grading — 어두운/중간/밝은 영역에 색조(chroma 주입)+광도. shadow.rgb=hueColor*sat,
    // shadow.a=lum. bb=(blending, balance).
    [[stitchable]] float4 colorGrade(
        coreimage::sample_t src,
        float4 shadow, float4 mid, float4 high, float2 bb
    ) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float y = dot(src.rgb, ycoef);
        float blending = bb.x, balance = bb.y;
        float pivot = clamp(0.5 + balance * 0.30, 0.15, 0.85);
        float wdt = mix(0.10, 0.50, blending);
        float sh = 1.0 - smoothstep(pivot - wdt, pivot + wdt, y);
        float hi = smoothstep(pivot - wdt, pivot + wdt, y);
        float md = clamp(1.0 - abs(y - pivot) / max(wdt, 0.001), 0.0, 1.0);
        float3 shc = shadow.rgb - dot(shadow.rgb, ycoef);
        float3 mdc = mid.rgb - dot(mid.rgb, ycoef);
        float3 hic = high.rgb - dot(high.rgb, ycoef);
        float3 rgb = src.rgb;
        rgb += sh * (shc * 0.75 + shadow.a * 0.22);
        rgb += md * (mdc * 0.75 + mid.a * 0.22);
        rgb += hi * (hic * 0.75 + high.a * 0.22);
        return float4(clamp(rgb, 0.0, 1.0), src.a);
    }

    // Calibration — R(0°)/G(120°)/B(240°) primary 의 hue 회전 + saturation 스케일(넓은 밴드).
    [[stitchable]] float4 calibrationPrimaries(coreimage::sample_t src, float3 hue, float3 sat) {
        float3 hsl = rgb2hsl(clamp(src.rgb, 0.0, 1.0));
        float centers[3] = {0.0, 0.333333, 0.666667};
        float hueAdj[3] = {hue.x, hue.y, hue.z};
        float satAdj[3] = {sat.x, sat.y, sat.z};
        float bw = 0.22;
        float wsum = 0.0, hs = 0.0, sf = 0.0;
        for (int i = 0; i < 3; i++) {
            float dd = abs(hsl.x - centers[i]);
            dd = min(dd, 1.0 - dd);
            float w = max(0.0, 1.0 - dd / bw);
            wsum += w; hs += w * hueAdj[i]; sf += w * satAdj[i];
        }
        if (wsum > 1e-4) { hs /= wsum; sf /= wsum; }
        float gate = smoothstep(0.03, 0.16, hsl.y);
        hsl.x = fract(hsl.x + hs * 0.08 * gate + 1.0);
        hsl.y = clamp(hsl.y * (1.0 + sf * gate), 0.0, 1.0);
        return float4(clamp(hsl2rgb(hsl), 0.0, 1.0), src.a);
    }

    [[stitchable]] float4 basicTone(
        coreimage::sample_t src,
        float contrastAmount,
        float densityAmount,
        float highlightAmount,
        float shadowAmount,
        float whitesAmount,
        float blacksAmount
    ) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float y = dot(src.rgb, ycoef);
        float target = y;

        float contrastPivot = 0.42;
        target = contrastPivot + (target - contrastPivot) * (1.0 + contrastAmount * 0.18);

        float midMask = smoothstep(0.08, 0.28, y) * (1.0 - smoothstep(0.56, 0.78, y));
        target -= densityAmount * 0.115 * midMask;

        // Highlights: Lightroom 규약 — 값을 올리면 명부가 밝아진다(내리면 recovery).
        // 기존엔 부호가 반대(-=)라 올릴수록 어두워지는 반전 버그였다.
        float highlightMask = smoothstep(0.30, 0.58, y);
        target += highlightAmount * 0.120 * highlightMask;

        // Shadows: 암부 디테일을 들어올리되, 절대 검정(y≈0)은 앵커로 고정해 바닥이 통째로
        // 회색으로 뜨는("붕 뜸") 현상을 막는다. 아래쪽 smoothstep(0,0.05)로 순검정 보호,
        // 위쪽 (1-smoothstep(0.20,0.44))로 중간톤 침범 차단 → 가시 암부에 집중.
        float shadowMask = smoothstep(0.0, 0.05, y) * (1.0 - smoothstep(0.20, 0.44, y));
        target += shadowAmount * 0.034 * shadowMask;

        float whiteMask = smoothstep(0.28, 0.62, y);
        target += whitesAmount * 0.150 * whiteMask;

        // Blacks: 흑점 제어. 순검정 바로 위 가장 어두운 띠를 움직이되, y=0 자체는 약하게 앵커링해
        // 검정이 통째로 milky 하게 뜨지 않도록 roll-off를 준다.
        float blackMask = smoothstep(0.0, 0.03, y) * (1.0 - smoothstep(0.10, 0.30, y));
        target += blacksAmount * 0.045 * blackMask;

        target = clamp(target, 0.0, 1.0);
        float3 rgb = src.rgb + float3(target - y);
        return float4(clamp(rgb, float3(0.0), float3(1.0)), src.a);
    }

    [[stitchable]] float4 parametricToneCurve(
        coreimage::sample_t src,
        float highlightsAmount,
        float lightsAmount,
        float darksAmount,
        float shadowsAmount,
        float shadowLow,
        float shadowHigh,
        float darkLow,
        float darkHigh,
        float lightLow,
        float lightHigh,
        float highlightLow,
        float highlightHigh
    ) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float y = dot(src.rgb, ycoef);

        // 절대 검정(y≈0)은 앵커로 고정해, Shadows를 올릴 때 바닥 전체가 회색으로 뜨는("붕 뜸")
        // 현상을 막는다. 가시 암부(y>0.045)에만 작용.
        float shadowMask = (1.0 - smoothstep(shadowLow, shadowHigh, y)) * smoothstep(0.0, 0.045, y);
        float darkMask = smoothstep(shadowLow, shadowHigh, y) * (1.0 - smoothstep(darkLow, darkHigh, y));
        float lightMask = smoothstep(darkLow, darkHigh, y) * (1.0 - smoothstep(lightLow, lightHigh, y));
        float highlightMask = smoothstep(highlightLow, highlightHigh, y);

        float delta =
            shadowsAmount * 0.160 * shadowMask +
            darksAmount * 0.155 * darkMask +
            lightsAmount * 0.165 * lightMask +
            highlightsAmount * 0.150 * highlightMask;
        float target = clamp(y + delta, 0.0, 1.0);
        float3 rgb = src.rgb + float3(target - y);
        return float4(clamp(rgb, float3(0.0), float3(1.0)), src.a);
    }

    // 필름 그레인 — zero-mean 휘도가중 노이즈. 기존 LinearDodge 그레인은 DC 바이어스가 있어
    // 암부를 통째로 밝게 띄웠다(사용자: "암부를 하얗게 붕 띄움"). 여기선 noise.r-0.5 로 평균 0을
    // 보장하고, 그레인이 미드톤에서 최대·순검정/순백 부근에서 약해지도록 휘도 가중(w)을 곱한다.
    [[stitchable]] float4 filmGrain(coreimage::sample_t src, coreimage::sample_t noise, float amount) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float y = dot(src.rgb, ycoef);
        float w = smoothstep(0.02, 0.16, y) * (1.0 - smoothstep(0.82, 1.0, y));
        float g = (noise.r - 0.5) * amount * w;
        return float4(clamp(src.rgb + float3(g), float3(0.0), float3(1.0)), src.a);
    }

    [[stitchable]] float4 scannerLowSatChroma(coreimage::sample_t src, coreimage::sample_t blur) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float y = dot(src.rgb, ycoef);
        float by = dot(blur.rgb, ycoef);
        float3 chroma = src.rgb - float3(y);
        float3 blurredChroma = blur.rgb - float3(by);
        float c = length(chroma);
        float lowSat = 1.0 - smoothstep(0.035, 0.160, c);
        float midHigh = smoothstep(0.24, 0.58, y);
        float magenta = smoothstep(0.006, 0.080, (src.r + src.b) * 0.5 - src.g);
        float amount = lowSat * midHigh * (0.38 + 0.42 * magenta);
        float3 mixedChroma = mix(chroma, blurredChroma, amount);
        mixedChroma = mix(mixedChroma, mixedChroma * 0.42, lowSat * magenta * 0.48);
        float3 rgb = clamp(float3(y) + mixedChroma, float3(0.0), float3(1.0));
        return float4(rgb, src.a);
    }

    [[stitchable]] float4 scannerMidtoneChroma(
        coreimage::sample_t src,
        coreimage::sample_t smallGuide,
        coreimage::sample_t largeGuide,
        float profileStrength
    ) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float y = dot(src.rgb, ycoef);
        float3 chroma = src.rgb - float3(y);
        float3 smallChroma = smallGuide.rgb - float3(0.5);
        smallChroma -= float3(dot(smallChroma, ycoef));
        float3 largeChroma = largeGuide.rgb - float3(0.5);
        largeChroma -= float3(dot(largeChroma, ycoef));

        float shadow = 1.0 - smoothstep(0.10, 0.34, y);
        float midtone = smoothstep(0.25, 0.47, y) * (1.0 - smoothstep(0.82, 0.94, y));
        float toneWeight = clamp(shadow * 1.10 + midtone * 0.78, 0.0, 1.0);
        float saturation = length(chroma);

        float lowMidChroma = smoothstep(0.018, 0.080, saturation) * (1.0 - smoothstep(0.180, 0.330, saturation));
        float vividGuard = 1.0 - smoothstep(0.150, 0.300, saturation);
        float warmPurple = smoothstep(0.015, 0.120, max(src.r - src.g, (src.r + src.b) * 0.5 - src.g));
        float yellowGreen = smoothstep(0.018, 0.110, max(src.g - src.b, (src.r + src.g) * 0.5 - src.b));
        float colorAxis = max(warmPurple, yellowGreen);

        float3 fineResidual = chroma - smallChroma;
        float3 coarseResidual = smallChroma - largeChroma;
        float fineSignal = smoothstep(0.006, 0.052, length(fineResidual));
        float coarseSignal = smoothstep(0.006, 0.044, length(coarseResidual));

        float fineGate = max(lowMidChroma, fineSignal * 0.65);
        float fineAmount = toneWeight * fineGate * vividGuard *
            (0.18 + 0.50 * profileStrength + 0.30 * fineSignal + 0.18 * colorAxis);
        float coarseAmount = toneWeight * vividGuard *
            (0.05 + 0.22 * profileStrength + 0.48 * coarseSignal * max(colorAxis, lowMidChroma));

        float3 mixedChroma = chroma
            - fineResidual * clamp(fineAmount, 0.0, 0.86)
            - coarseResidual * clamp(coarseAmount, 0.0, 0.62);

        float axis = toneWeight * warmPurple * vividGuard * (0.55 + 0.45 * profileStrength);
        mixedChroma.r *= 1.0 - axis * 0.155;
        mixedChroma.b *= 1.0 - axis * 0.190;
        float3 rgb = clamp(float3(y) + mixedChroma, float3(0.0), float3(1.0));
        return float4(rgb, src.a);
    }

    [[stitchable]] float4 mainTargetGrade(coreimage::sample_t src) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float y = dot(src.rgb, ycoef);
        float3 chroma = src.rgb - float3(y);
        float c = length(chroma);

        float shadowMid = smoothstep(0.035, 0.16, y) * (1.0 - smoothstep(0.64, 0.86, y));
        float redAxis = smoothstep(0.015, 0.16, src.r - max(src.g, src.b));
        float weakGreenAxis = smoothstep(0.010, 0.12, src.g - max(src.r, src.b));
        float lowChroma = 1.0 - smoothstep(0.050, 0.24, c);

        chroma = mix(chroma, chroma * 0.50, shadowMid * lowChroma * 0.55);
        // 빨강 억제(랩 스캐너 muted-red 룩)는 중간톤에서 유지하되, **명부(밝은) 빨강 피사체**는
        // 보호한다. 명부 빨강까지 억제하면 밝은 빨강(꽃·옷의 하이라이트)이 과도 탈색됐다
        // (측정: 명부 빨강 redDominance 0.075 ≪ 중간톤 0.32 — 명부에서만 비정상적으로 낮음).
        // (1 - smoothstep(0.55,0.80,y)) 로 명부에서 억제를 풀어, 중간톤 muted-red 의도는 유지한다.
        float redDesat = shadowMid * redAxis * (1.0 - smoothstep(0.50, 0.70, y));
        chroma.r *= 1.0 - redDesat * 0.62;
        chroma.b *= 1.0 - redDesat * 0.16;
        chroma.g *= 1.0 + shadowMid * weakGreenAxis * 0.24;

        float3 rgb = clamp(float3(y) + chroma, float3(0.0), float3(1.0));
        return float4(rgb, src.a);
    }

    // 사용자 노이즈 제거 — **블러가 아니라 노이즈 픽셀만 골라 교체(selective despeckle)**.
    //   • 노이즈 픽셀 = 국소 median에서 크게 벗어난 outlier(고립된 grain/색 speckle).
    //   • 정상 픽셀(median에 가까움) = 그대로 둠 → 디테일/엣지/텍스처 보존(뭉개기 없음).
    //   • luma outlier(암부 grain 픽셀) → 3x3 median luma로 교체.
    //   • chroma outlier(컬러 노이즈 픽셀) → 더 큰 median chroma로 교체.
    //   • tone gate: 암부/중간톤만(명부 보호). strength가 검출 임계를 넓힌다(강할수록 공격적).
    [[stitchable]] float4 despeckle(
        coreimage::sample_t src,
        coreimage::sample_t lumaMed,     // 3x3 median (grain용)
        coreimage::sample_t chromaMed,   // 더 큰 median (색 speckle용)
        coreimage::sample_t broadChroma,
        coreimage::sample_t lumaField,
        float strength
    ) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float y  = dot(src.rgb, ycoef);
        float ly = dot(lumaMed.rgb, ycoef);
        float cy = dot(chromaMed.rgb, ycoef);
        float by = dot(broadChroma.rgb, ycoef);
        float fy = dot(lumaField.rgb, ycoef);
        float3 sc = src.rgb - float3(y);
        float3 mc = chromaMed.rgb - float3(cy);
        float3 bc = broadChroma.rgb - float3(by);
        float saturation = length(sc);

        // grain은 전 톤에 퍼져 있으므로 전 톤에서 제거. 클리핑 직전(거의 흰색)만 보호.
        float tone = 1.0 - smoothstep(0.93, 0.995, y);
        float edgeGuard = 1.0 - smoothstep(0.030, 0.115, abs(y - by));
        edgeGuard = min(edgeGuard, 1.0 - smoothstep(0.006, 0.028, abs(ly - cy)));
        float colorGuard = 1.0 - smoothstep(0.145, 0.285, saturation);

        // luma grain 픽셀: median에서 벗어난 정도(=outlier)만 교체. 정상/엣지 픽셀은 median과 가까워 보존.
        float lumaDev = abs(y - ly);
        float lLo = mix(0.030, 0.003, strength), lHi = mix(0.080, 0.020, strength);
        float lumaW = smoothstep(lLo, lHi, lumaDev) * tone * (0.35 + 0.65 * edgeGuard);
        float shadowBase = 1.0 - smoothstep(0.42, 0.68, cy);
        float brightSpike = smoothstep(0.010, 0.075, y - cy) * shadowBase * tone;
        float outY = mix(y, ly, lumaW);
        outY = mix(outY, cy, clamp(brightSpike, 0.0, 0.92));
        float lumaFieldDev = abs(outY - fy);
        float fieldW = smoothstep(mix(0.020, 0.004, strength), mix(0.065, 0.022, strength), lumaFieldDev);
        fieldW *= shadowBase * tone * edgeGuard * (0.25 + 0.55 * strength);
        outY = mix(outY, fy, clamp(fieldW, 0.0, 0.68));

        // 컬러 노이즈 픽셀: 국소 median chroma에서 벗어난 outlier만 교체. 실색(균일/구조적)은 보존.
        float chromaDev = length(sc - mc);
        float cLo = mix(0.025, 0.003, strength), cHi = mix(0.070, 0.018, strength);
        float chromaW = smoothstep(cLo, cHi, chromaDev) * tone * (0.45 + 0.55 * colorGuard);
        float3 outC = mix(sc, mc, chromaW);
        float blotchDev = length(outC - bc);
        float blotchW = smoothstep(mix(0.030, 0.006, strength), mix(0.090, 0.026, strength), blotchDev);
        blotchW *= tone * edgeGuard * colorGuard * (0.35 + 0.55 * strength);
        outC = mix(outC, bc, clamp(blotchW, 0.0, 0.88));
        float neutralSurface = (1.0 - smoothstep(0.060, 0.240, length(bc))) * edgeGuard * tone;
        float chromaFieldW = smoothstep(mix(0.014, 0.003, strength), mix(0.055, 0.018, strength), length(outC - bc));
        outC = mix(outC, outC * 0.46 + bc * 0.54, clamp(chromaFieldW * neutralSurface * strength, 0.0, 0.72));

        return float4(clamp(float3(outY) + outC, float3(0.0), float3(1.0)), src.a);
    }

    // Constant-hue gamut soft-clip. 채도/톤 부스트가 채널을 [0,1] 밖으로 밀면, 채널별 하드
    // 클립이 채널 비율을 깨뜨려 hue가 틀어진다(명부 노랑, 암부/미드 보라, 채널별 크러시).
    // 대신 luma는 보존한 채 chroma만 줄여(중립으로 desaturate) gamut 안으로 들인다.
    [[stitchable]] float4 gamutSoftClip(coreimage::sample_t src) {
        float3 rgb = src.rgb;
        float y = clamp(dot(rgb, float3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
        float3 c = rgb - float3(y);
        // 가장 큰 t∈[0,1]: y + t*c 가 채널별로 [0,1]에 들어오는 값.
        float tr = c.r > 1e-5 ? (1.0 - y) / c.r : (c.r < -1e-5 ? (-y) / c.r : 1.0);
        float tg = c.g > 1e-5 ? (1.0 - y) / c.g : (c.g < -1e-5 ? (-y) / c.g : 1.0);
        float tb = c.b > 1e-5 ? (1.0 - y) / c.b : (c.b < -1e-5 ? (-y) / c.b : 1.0);
        float t = clamp(min(1.0, min(tr, min(tg, tb))), 0.0, 1.0);
        return float4(clamp(float3(y) + t * c, 0.0, 1.0), src.a);
    }

    // 명부 chroma desaturation (HIGHLIGHT_TONE_REDESIGN.md §5 옵션 C).
    // per-channel 반전/AutoLevels 가 명부에서 채널 비율을 틀어 남긴 "명부 따뜻함"(중립이어야 할
    // 밝은 회색이 R>B 로 노랗게, 측정 R-B≈10~13)을 제거한다. luma 는 보존하고, y 가 startY 위로
    // 갈수록 chroma 를 0(중립 white)으로 수렴시킨다. 이미 채도가 낮은(거의 중립) 명부일수록 강하게
    // 당기되, 채도가 높은 명부(노을·네온 등 의도된 색)는 desat 을 약하게 둬 탈색을 막는다
    // (lowChromaBias: 고채도 보호). darktable sigmoid 의 "rgb-ratio 명부 desaturation" 과 동형.
    [[stitchable]] float4 highlightDesaturate(coreimage::sample_t src, float strength, float startY) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float y = clamp(dot(src.rgb, ycoef), 0.0, 1.0);
        float3 chroma = src.rgb - float3(y);
        float sat = length(chroma);
        float hiMask = smoothstep(startY, 1.0, y);
        // 고채도(의도된 색)는 보호: 채도가 클수록 desat 약화. 중립 부근(작은 sat)만 강하게 중립화.
        float lowChromaBias = 1.0 - smoothstep(0.06, 0.22, sat);
        float desat = hiMask * strength * lowChromaBias;
        float3 rgb = clamp(float3(y) + chroma * (1.0 - desat), 0.0, 1.0);
        return float4(rgb, src.a);
    }

    // 8bit 양자화 banding dithering. sRGB 인코딩된 src 에 ±0.5/255(8bit 1스텝 이내) 노이즈를
    // 더한다. noise 는 [0,1] white noise. alpha 는 src 그대로 보존(LinearDodge 의 알파 합성 버그
    // 회피). banding 경계 픽셀만 인접 양자화 스텝으로 분산되고 디테일/평균 톤은 보존된다.
    [[stitchable]] float4 ditherAdd(coreimage::sample_t src, coreimage::sample_t noise) {
        float3 d = (noise.rgb - float3(0.5)) / 255.0;
        return float4(src.rgb + d, src.a);
    }
    """
}
