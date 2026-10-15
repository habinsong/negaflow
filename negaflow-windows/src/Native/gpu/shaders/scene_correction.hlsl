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
// **판정은 여기서 하지 않습니다.** 백분위·중립축 적합·게이트는 CPU 의 공개 함수
// (`plan_scene_auto_levels` / `plan_scene_neutral_balance`)가 정하고, 이 셰이더는
// 그 결과(scale·bias, 채널별 지수·게인)를 받아 화소에만 적용합니다. 규칙을 두 벌로 만들면
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
    // 자동 색상 계수입니다. Cube[0].rgb = 채널별 지수, Cube[1].rgb = 채널별 게인. 나머지는
    // 쓰지 않습니다(배치를 바꾸지 않으려고 크기를 그대로 둡니다).
    float4 Cube[24];
};

[numthreads(8, 8, 1)]
void SceneAutoLevelsMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];
    // 아래만 0 으로 묶고 위는 확장값으로 남깁니다 — CPU `scene_auto_levels_upper_clamp`.
    float3 color = clamp((source.rgb * LevelScale.rgb) + LevelBias.rgb, 0.0, 10000.0);
    Destination[coordinate] = float4(color, source.a);
}

// CPU `power_gain` 그대로 — c' = gain·c^exponent. 0 이하 값은 그대로 둡니다.
// `abs` 는 여기서 **항등**입니다 — 이 가지는 `value > 0` 일 때만 돕니다. fxc 가 `pow` 의 밑을
// 정적으로 양수라고 증명하지 못해 경고(X3571, `/WX` 라 오류)를 내므로 답니다.
float PowerGain(float value, float exponent, float gain) {
    return value > 0.0 ? gain * pow(abs(value), exponent) : value;
}

[numthreads(8, 8, 1)]
void SceneNeutralBalanceMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];
    float3 color;
    color.r = PowerGain(source.r, Cube[0].r, Cube[1].r);
    color.g = PowerGain(source.g, Cube[0].g, Cube[1].g);
    color.b = PowerGain(source.b, Cube[0].b, Cube[1].b);
    Destination[coordinate] = float4(color, source.a);
}
