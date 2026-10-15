import CoreImage

// 선명도·부분 대비(DetailEnhancement) 커널. 둘 다 **감마(sRGB 인코딩) 휘도**에서 디테일을 다루고,
// 결과는 휘도 비율로 RGB 에 실어 색상·채도를 건드리지 않는다. linear RGB 채널별 언샤프는 밝은 쪽
// 헤일로가 커지고(선형에서 같은 진폭은 밝은 쪽이 더 크다) 채널마다 따로 날카로워져 색 테두리가 생긴다.
extension ChromabaseMetalKernels {
    static let detailKernelSources: [MetalKernelSource] = [
        MetalKernelSource(name: "detailGammaLuma", body: """
    // 디테일 계산용 안내 영상: 감마 휘도(0…1). 가이디드 필터·블러의 입력이다.
    [[stitchable]] float4 detailGammaLuma(coreimage::sample_t src) {
        float y = dot(src.rgb, float3(0.2126, 0.7152, 0.0722));
        float g = srgbEncodeLuma(clamp(y, 0.0, 1.0));
        return float4(g, g, g, 1.0);
    }
    """),
        MetalKernelSource(name: "detailSharpen", body: """
    // 선명도: 감마 휘도 언샤프. threshold 아래의 미세 진폭(스캐너 노이즈·그레인 바닥)은 부드럽게
    // 깎아(소프트 코어링) 증폭하지 않고, 증폭분은 halo 로 부드럽게 묶어 큰 경계의 헤일로를 막는다.
    // 암부 바닥: 원 휘도의 45% 와 ≈2/255 아래로는 내리지 않는다(검정 붕괴·0 끝 빈 방지).
    [[stitchable]] float4 detailSharpen(
        coreimage::sample_t src,
        coreimage::sample_t blurred,
        float amount,
        float threshold,
        float halo
    ) {
        float3 s = src.rgb;
        float y = dot(s, float3(0.2126, 0.7152, 0.0722));
        if (y <= 1e-5) { return src; }
        float yO = srgbEncodeLuma(y);
        float d = min(yO, 1.0) - blurred.r;
        float cored = d * (d * d / (d * d + threshold * threshold));
        float lift = halo * tanh(amount * cored / halo);
        float floorY = max(yO * 0.45, min(yO, 0.008));
        float yN = max(yO + lift, floorY);
        return float4(s * (srgbDecodeLuma(yN) / y), src.a);
    }
    """),
        MetalKernelSource(name: "detailLocalContrast", body: """
    // 부분 대비: 경계 보존 베이스(가이디드 필터 계수 meanA·meanB)에 대한 디테일을 키우거나(+)
    // 줄인다(−). 계수 a 는 그 자리가 경계인 정도다(경계 → 1, 질감·평면 → 0) — (1−a) 를 곱해 큰
    // 경계 둘레는 건드리지 않는다(가이디드 필터 헤일로·번짐 제거). 미드톤 가중(4g(1−g))으로 암부·
    // 명부는 덜 건드린다. − 는 흐림 섞기가 아니라 같은 분해에서 디테일만 줄이는 것이다.
    [[stitchable]] float4 detailLocalContrast(
        coreimage::sample_t src,
        coreimage::sample_t meanA,
        coreimage::sample_t meanB,
        float amount,
        float halo
    ) {
        float3 s = src.rgb;
        float y = dot(s, float3(0.2126, 0.7152, 0.0722));
        if (y <= 1e-5) { return src; }
        float yO = srgbEncodeLuma(y);
        float g = clamp(yO, 0.0, 1.0);
        float base = clamp(meanA.r * g + meanB.r, 0.0, 1.0);
        float weight = clamp(4.0 * g * (1.0 - g), 0.0, 1.0);
        float texture = 1.0 - clamp(meanA.r, 0.0, 1.0);
        float lift = halo * tanh(amount * weight * texture * (g - base) / halo);
        float floorY = max(yO * 0.45, min(yO, 0.008));
        float yN = max(yO + lift, floorY);
        return float4(s * (srgbDecodeLuma(yN) / y), src.a);
    }
    """),
    ]
}
