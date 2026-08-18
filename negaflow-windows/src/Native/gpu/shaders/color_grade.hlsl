// macOS `ChromabaseMetalKernels.swift:101` `[[stitchable]] float4 colorGrade(...)`.
// Windows CPU 판은 `imaging/color_grading.cpp` `apply_color_grading` 이고, 이 셰이더는
// 그것과 화소값이 같아야 합니다(동치 시험 허용 오차 1e-5).
//
// macOS 는 색조(tint)를 그대로 넘겨 화소마다 `shc = shadow.rgb - dot(shadow.rgb, ycoef)` 를
// 다시 계산합니다. Windows CPU 는 그 값을 `prepare_region` 으로 **한 번만** 계산해 둡니다 —
// 화소마다 같은 값이라 결과는 같고 계산은 적습니다. 이 셰이더는 Windows CPU 를 따릅니다.
// 오프셋·피벗·폭은 `imaging::prepare_color_grading` 이 만든 것을 그대로 받습니다.
// **여기서 다시 계산하지 마십시오** — 두 벌이 되면 조용히 갈라집니다.

#include "tone_shared.hlsli"

cbuffer ColorGradeConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    float3 ShadowOffset;
    float Pivot;
    float3 MidtoneOffset;
    float Width;
    float3 HighlightOffset;
    float Padding1;
};

[numthreads(8, 8, 1)]
void ColorGradeMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];

    float sourceLuma = dot(source.rgb, LumaCoefficients);
    float transition = smoothstep(Pivot - Width, Pivot + Width, sourceLuma);
    float shadowWeight = 1.0 - transition;
    float highlightWeight = transition;
    // CPU 판은 `width` 로 그대로 나눕니다. `width = 0.10 + 0.40*blending` 이라 항상 0.10 이상이므로
    // macOS 의 `max(wdt, 0.001)` 가드는 이 정의역에서 아무 값도 바꾸지 않습니다.
    float midtoneWeight = clamp(1.0 - (abs(sourceLuma - Pivot) / Width), 0.0, 1.0);

    // CPU 판과 같은 순서로 더합니다 — 그림자 → 미드톤 → 명부.
    float3 rgb = source.rgb;
    rgb += shadowWeight * ShadowOffset;
    rgb += midtoneWeight * MidtoneOffset;
    rgb += highlightWeight * HighlightOffset;

    Destination[coordinate] = float4(clamp(rgb, 0.0, 1.0), source.a);
}
