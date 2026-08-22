// 자동 레벨 · 자동 중성 균형의 **적용** 커널 둘입니다 — 우측탭 Auto Levels /
// Auto Neutral Balance.
//
// CPU 판 : `imaging/scene_correction.cpp` `apply_auto_levels` / `apply_neutral_balance`
// 표본 : `shaders/scene_sample_grid.hlsl`
//
// 왜 GPU 인가 — 이 단계는 반전 바로 뒤에 있고, CPU 로 돌리려면 화소를 **호스트로 내려야**
// 합니다. 그 한 번의 `flush_resident()` 때문에 뒤따르는 톤·필름룩·마무리·발행이 전부
// 호스트에서 돌았습니다. 실측(1536x1026 슬라이더 8틱): 왕복 다운로드 1,374 MB.
//
// **판정은 여기서 하지 않습니다.** 백분위·중앙값·게이트는 CPU 의 공개 함수
// (`plan_scene_auto_levels` / `plan_scene_neutral_balance`)가 정하고, 이 셰이더는
// 그 결과(scale·bias·32칸 큐브)를 받아 화소에만 적용합니다. 규칙을 두 벌로 만들면
// 프리뷰와 내보내기가 다른 사진이 됩니다.

Texture2D<float4> Source : register(t0);
RWTexture2D<float4> Destination : register(u0);

cbuffer SceneCorrectionConstants : register(b0) {
    // GpuPointwiseExtent — 16바이트.
    uint2 Extent;
    float2 ExtentPad;
    // 자동 레벨 계수입니다.
    float4 LevelScale;
    float4 LevelBias;
    // 32칸 큐브 세 벌(적·녹·청 순서). HLSL 상수 배열은 항목마다 16바이트로 채워지므로
    // float4 로 묶어 채널당 8개 레지스터를 씁니다.
    float4 Cube[24];
};

[numthreads(8, 8, 1)]
void SceneAutoLevelsMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];
    float3 color = saturate((source.rgb * LevelScale.rgb) + LevelBias.rgb);
    Destination[coordinate] = float4(color, source.a);
}

// CPU `cube_curve` 그대로 — 32칸 표를 선형 보간합니다. 표는 호스트가 채널마다 한 번
// 만들어 넘깁니다(화소마다 `pow` 를 부르지 않습니다).
float CubeEntry(uint channelBase, uint index) {
    float4 packed = Cube[channelBase + (index >> 2u)];
    uint lane = index & 3u;
    return lane == 0u ? packed.x
         : lane == 1u ? packed.y
         : lane == 2u ? packed.z
                      : packed.w;
}

float CubeCurve(float value, uint channelBase) {
    float position = saturate(value) * 31.0;
    uint lower = uint(position);
    uint upper = min(31u, lower + 1u);
    float t = position - float(lower);
    float a = CubeEntry(channelBase, lower);
    float b = CubeEntry(channelBase, upper);
    return a + ((b - a) * t);
}

[numthreads(8, 8, 1)]
void SceneNeutralBalanceMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];
    float3 color;
    color.r = CubeCurve(source.r, 0u);
    color.g = CubeCurve(source.g, 8u);
    color.b = CubeCurve(source.b, 16u);
    Destination[coordinate] = float4(color, source.a);
}
