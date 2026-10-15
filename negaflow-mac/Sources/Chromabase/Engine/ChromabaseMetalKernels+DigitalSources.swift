import CoreImage

// 디지털 소스 전용 필름 시뮬레이션 커널. 필름 스캔은 호출하지 않는다.
// 커널마다 독립 Metal 라이브러리로 컴파일된다(ChromabaseMetalKernels 참고).
extension ChromabaseMetalKernels {
    static let digitalKernelSources: [MetalKernelSource] = [
        MetalKernelSource(name: "digitalSceneReconstruct", body: """
    // 디스플레이 렌더된 값 → 필름이 받는 노출(scene-linear) 추정.
    // 카메라가 이미 씌운 숄더를 역으로 풀어 명부에 헤드룸을 되돌린다. 클리핑으로 사라진
    // 정보는 복원되지 않으며, 이는 재구성이지 복원이 아니다.
    // p = (a, dmin, scale, _). a/dmin 이 확장 곡선을, scale 이 중간 회색 앵커를 맞춘다.
    [[stitchable]] float4 digitalSceneReconstruct(coreimage::sample_t src, float4 p) {
        float3 v = src.rgb;
        float3 om = float3(1.0) - v;
        float3 denom = 0.5 * (om + sqrt(om * om + 4.0 * p.y * p.y));
        return float4(p.x * v / denom * p.z, src.a);
    }
    """),
        MetalKernelSource(name: "digitalFilmDensity", body: """
    // 노출 → 채널별 특성곡선 밀도. 중간 회색(0.18)에서 밀도 0 이 되도록 중심을 맞춘다.
    // polarity +1 = 네거티브(노출↑ → 밀도↑), -1 = 반전.
    // exposureScale 은 장면의 노출 범위를 그 유제의 관용도에 맞춰 옮기는 비율이다. 관용도가
    // 좁은 반전 필름일수록 작아진다 — 좁은 필름에 넓은 장면을 그대로 밀어 넣으면 명부가
    // 곡선 밖으로 나가 계조가 남지 않는다.
    // gammaPolarity = (γR, γG, γB, polarity), limits = (Lhi, Llo, nShoulder, nToe)
    [[stitchable]] float4 digitalFilmDensity(coreimage::sample_t src,
                                             float4 gammaPolarity,
                                             float4 limits,
                                             float exposureScale,
                                             float4 layerSpeed,
                                             float4 layerDmax) {
        float3 e = max(src.rgb, float3(1e-5));
        // 감광층은 감도가 서로 다르게 설계된다. 층마다 곡선이 노출 축에서 어긋나 있고,
        // 그 어긋남이 밝기대별로 색이 갈리는 크로스오버의 물리적 출처다.
        float3 stops = (log2(e / float3(0.18)) + layerSpeed.rgb) * exposureScale;
        float3 d = gammaPolarity.rgb * 0.30103 * stops * gammaPolarity.w;
        // 층별 최대 밀도도 같지 않다 — 적감(시안 형성) 층이 가장 높은 Dmax 로 눕는다.
        float3 hi = float3(
            softLimit(max(d.x, 0.0), limits.x * layerDmax.x, limits.z),
            softLimit(max(d.y, 0.0), limits.x * layerDmax.y, limits.z),
            softLimit(max(d.z, 0.0), limits.x * layerDmax.z, limits.z)
        );
        float3 lo = float3(
            softLimit(max(-d.x, 0.0), limits.y * layerDmax.x, limits.w),
            softLimit(max(-d.y, 0.0), limits.y * layerDmax.y, limits.w),
            softLimit(max(-d.z, 0.0), limits.y * layerDmax.z, limits.w)
        );
        return float4(hi - lo, src.a);
    }
    """),
        MetalKernelSource(name: "digitalInterImage", body: """
    // DIR 커플러의 층간 억제(inter-image effect). 한 층의 밀도가 이웃 층의 현상을 억제한다.
    // 중립 대비로 정규화하므로 무채색은 정확히 보존되고 유채색만 채널 간격이 벌어진다 —
    // 색 대비를 중립 대비에서 분리하는 것이 DIR 커플러가 채도를 만드는 실제 메커니즘이다.
    [[stitchable]] float4 digitalInterImage(coreimage::sample_t src, float4 k) {
        float3 d = src.rgb;
        float3 kk = max(k.rgb, float3(0.0));
        float3 others = (float3(d.x + d.y + d.z) - d) * 0.5;
        return float4((d - kk * others) / max(float3(1.0) - kk, float3(1e-3)), src.a);
    }
    """),
        MetalKernelSource(name: "digitalPrintPaper", body: """
    // 네거티브 밀도 → 인화 노출 → RA-4 인화지 밀도 → 반사율.
    // 네거티브의 낮은 감마(≈0.6)를 인화지의 높은 감마(≈1.7)가 되살리는 2단 구조가
    // 네거티브 특유의 "늦게 눕는 명부 + 살아 있는 암부"를 만든다.
    // paper = (γ, Dmax, Dmin, n)
    [[stitchable]] float4 digitalPrintPaper(coreimage::sample_t src, float4 paper) {
        float3 stops = -src.rgb / 0.30103;
        float3 dp = paper.x * 0.30103 * stops;
        float3 hi = softLimit3(max(dp, float3(0.0)), paper.y, paper.w);
        float3 lo = softLimit3(max(-dp, float3(0.0)), paper.z, paper.w);
        return float4(0.18 * pow(float3(10.0), -(hi - lo)), src.a);
    }
    """),
        MetalKernelSource(name: "digitalReversalTransmit", body: """
    // 반전 필름은 인화 단계가 없다. 밀도를 그대로 투과율로 읽는다.
    // p = (Dmax, Dmin, n, _)
    [[stitchable]] float4 digitalReversalTransmit(coreimage::sample_t src, float4 p) {
        float3 d = src.rgb;
        float3 hi = softLimit3(max(d, float3(0.0)), p.x, p.z);
        float3 lo = softLimit3(max(-d, float3(0.0)), p.y, p.z);
        return float4(0.18 * pow(float3(10.0), -(hi - lo)), src.a);
    }
    """),
        MetalKernelSource(name: "digitalHalation", body: """
    // 산란 + 헐레이션. 에멀전 내부 산란(작은 반경)과 베이스 반사(큰 반경, 다중 바운스)를
    // 나눠 합성한다. 되돌아온 빛은 적색 층을 먼저 때리므로 R ≫ G > B 로 실린다.
    // 더하지 않고 원본에서 덜어내 재분배하므로 총 광량이 늘지 않는다.
    [[stitchable]] float4 digitalHalation(coreimage::sample_t src,
                                          coreimage::sample_t nearBlur,
                                          coreimage::sample_t farBlur,
                                          coreimage::sample_t wideBlur,
                                          float4 scatter, float4 halation) {
        float3 s = max(scatter.rgb, float3(0.0));
        float3 h = max(halation.rgb, float3(0.0));
        float3 far = farBlur.rgb * 0.68 + wideBlur.rgb * 0.32;
        float3 keep = max(float3(1.0) - s - h, float3(0.0));
        return float4(src.rgb * keep + nearBlur.rgb * s + far * h, src.a);
    }
    """),
        MetalKernelSource(name: "digitalToDisplayGamma", body: """
    // 색 조정 스테이지(그레이딩·믹서·캘리브레이션)는 표시 도메인 0…1 을 전제로 만들어졌다.
    // 가상 현상 결과는 선형 반사율이므로, 그 스테이지들을 태우기 전후로 도메인을 옮긴다.
    [[stitchable]] float4 digitalToDisplayGamma(coreimage::sample_t src) {
        return float4(digitalLinearToSRGB(src.rgb), src.a);
    }
    """),
        MetalKernelSource(name: "digitalToLinearLight", body: """
    [[stitchable]] float4 digitalToLinearLight(coreimage::sample_t src) {
        return float4(digitalSRGBToLinear(src.rgb), src.a);
    }
    """),
        MetalKernelSource(name: "digitalFilmColor", body: """
    // 필름 스톡의 색 시그니처. 대비/계조는 가상 현상이 이미 만들었으므로 여기서는 색만 얹는다.
    // 계수가 sRGB 감마 도메인 기준이라 그 도메인으로 옮겨 적용하고 되돌린다.
    // mR/mG/mB = 색 매트릭스 행(.w = 채널 lift). hue 앵커 6개는 iieHueA 전체와 iieHueB.xy 에
    // 담고, inter-image 채도 강도는 iieHueB.z 에 둔다.
    [[stitchable]] float4 digitalFilmColor(coreimage::sample_t src,
                                           float4 mR, float4 mG, float4 mB,
                                           float4 shadowTint, float4 highlightTint,
                                           float4 iieHueA, float4 iieHueB) {
        constexpr float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float3 v = digitalLinearToSRGB(src.rgb) + float3(mR.w, mG.w, mB.w);
        v = max(float3(dot(mR.rgb, v), dot(mG.rgb, v), dot(mB.rgb, v)), float3(0.0));

        float yl = clamp(dot(v, ycoef), 0.0, 1.0);
        v += shadowTint.rgb * (1.0 - yl) * (1.0 - yl) + highlightTint.rgb * yl * yl;

        float y = dot(v, ycoef);
        float chroma = max(v.r, max(v.g, v.b)) - min(v.r, min(v.g, v.b));
        float expW = smoothstep(0.12, 0.72, y);
        float protectW = smoothstep(0.02, 0.14, chroma);
        float hueW = 1.0 + digitalHueBand(digitalHueDegrees(v), iieHueA, iieHueB);
        float sat = 1.0 + iieHueB.z * expW * protectW * hueW;
        v = float3(y) + (v - float3(y)) * sat;

        return float4(digitalSRGBToLinear(max(v, float3(0.0))), src.a);
    }
    """),
        MetalKernelSource(name: "digitalFilmGrainDensity", body: """
    // 밀도 의존 그레인. 물리 granularity 는 밀도의 제곱근을 따라 커지고(Selwyn), 지각되는
    // 거칠기는 밀도 1.0 부근에서 가장 크다. 두 특성을 곱해 진폭을 정한다. 노이즈는 밀도
    // 도메인에서 더한다 — 필름 그레인은 가산 오버레이가 아니라 곱셈 변조이기 때문이다.
    // p = (amplitude, chromaRatio, _, _)
    [[stitchable]] float4 digitalFilmGrainDensity(coreimage::sample_t src,
                                                  coreimage::sample_t noise,
                                                  float4 p) {
        float3 v = max(src.rgb, float3(1e-5));
        float3 dens = -log10(v / float3(0.18));
        float3 physical = sqrt(max(dens, float3(0.0)) + float3(0.02));
        float3 t = (dens - float3(1.0)) / float3(1.15);
        float3 perceptual = exp(-t * t);
        float3 amp = p.x * physical * perceptual;
        float3 n = noise.rgb - float3(0.5);
        float nl = (n.x + n.y + n.z) / 3.0;
        n = mix(float3(nl), n, p.y);
        return float4(0.18 * pow(float3(10.0), -(dens + n * amp)), src.a);
    }
    """),
        MetalKernelSource(name: "digitalBWFilm", body: """
    // 흑백 유제 응답. 두 도메인을 나눠 쓴다.
    //   • 분광 합성(RGB→그레이)은 **선형 광 도메인**에서 한다. 유제가 받는 것은 빛의 양이지
    //     감마 인코딩된 값이 아니다. 감마 도메인에서 합치면 오소/적외처럼 가중치가 극단적인
    //     유제에서 밝기가 눈에 띄게 어긋난다.
    //   • 특성곡선은 **sRGB 감마 도메인**에서 적용한다. 대비·토우·숄더는 지각 균등 축에서
    //     정의해야 밝기대별 효과가 고르게 실린다(엔진의 다른 톤 스테이지와 같은 규약).
    // 1 을 넘는 확장값은 곡선 밖으로 빼 두었다가 되돌려 준다 — 작업 이미지의 관용도를
    // 여기서 잘라 내면 표시/내보내기 경계가 할 일을 미리 망친다.
    // w  = (weightR, weightG, weightB, intensity)
    // c0 = (contrast, toe, shoulder, deepen)
    // c1 = (black, white, _, _)
    [[stitchable]] float4 digitalBWFilm(coreimage::sample_t src,
                                        float4 w, float4 c0, float4 c1) {
        float y = dot(max(src.rgb, float3(0.0)), w.xyz);
        float t = clamp(y, 0.0, 1.0);
        float over = y - t;

        float g = digitalLinearToSRGB(float3(t)).x;

        // 1) 대비 — 표준 현상 기준선에서의 편차. 음수면 곡선을 반대로 눕혀 대비를 낮춘다.
        float s = g * g * g * (g * (g * 6.0 - 15.0) + 10.0);
        float r = clamp(g + (s - g) * c0.x, 0.0, 1.0);

        // 2) 토우 — 긴 토우는 암부를 들어 올리고, 곧은 토우는 암부를 더 떨군다.
        float low = 1.0 - r;
        r = clamp(r + c0.y * low * low * low, 0.0, 1.0);

        // 3) 숄더 — 넓은 관용도는 명부를 눕혀 담고, 좁은 관용도는 명부를 빨리 붙인다.
        r = clamp(r + c0.z * r * r * r, 0.0, 1.0);

        // 4) 반전은 인화지가 뒤를 받치지 않아 검정이 바닥까지 간다. 중간톤은 건드리지 않는다.
        float d = 1.0 - r;
        r = clamp(r * (1.0 - c0.w * d * d * d), 0.0, 1.0);

        // 5) 매체의 흑·백 한계. 인화지는 순흑에 붙지 않고, 반전은 붙는다.
        r = clamp(c1.x + r * (c1.y - c1.x), 0.0, 1.0);

        // 강도는 지각 도메인에서 섞는다. 0 이면 유제 특성이 사라지고 중립 그레이만 남는다.
        r = mix(g, r, w.w);

        float outv = digitalSRGBToLinear(float3(r)).x + over;
        return float4(float3(outv), src.a);
    }
    """),
    ]
}
