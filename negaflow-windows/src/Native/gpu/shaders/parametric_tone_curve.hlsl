// macOS `ChromabaseMetalKernels.swift:242` `[[stitchable]] float4 parametricToneCurve(...)`.
// Windows CPU 판은 `imaging/tone_mapping.cpp:143` `apply_parametric_tone_curve` 이고,
// 이 셰이더는 그것과 화소값이 같아야 합니다(동치 시험 허용 오차 1e-5).
//
// 매듭(macOS `ParametricToneCurve`)은 CPU 가 장면 백분위와 슬라이더로 한 번 풀어 넘깁니다
// (`imaging::parametric_tone_curve_shape`). 양 끝 x0=0·x5=1 은 고정이고 안쪽 네 매듭(KnotX·KnotY)과
// 여섯 기울기(TangentLow.xyz = m0..m2, TangentHigh.xyz = m3..m5)가 상수입니다. 화소마다는 인코딩
// 휘도 위의 단조 3차 Hermite 하나입니다.

#include "tone_shared.hlsli"

cbuffer ParametricToneCurveConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    float4 KnotX;
    float4 KnotY;
    float4 TangentLow;
    float4 TangentHigh;
};

[numthreads(8, 8, 1)]
void ParametricToneCurveMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];

    float3 safeRgb = ToneSafeUnitRGB(source.rgb);
    float sourceLuma = dot(safeRgb, LumaCoefficients);
    float g = LinearToSrgbEncoded(clamp(sourceLuma, 0.0, 1.0));

    float x0 = 0.0;
    float x1 = KnotX.x;
    float y0 = 0.0;
    float y1 = KnotY.x;
    float m0 = TangentLow.x;
    float m1 = TangentLow.y;
    if (g >= KnotX.x) { x0 = KnotX.x; x1 = KnotX.y; y0 = KnotY.x; y1 = KnotY.y; m0 = TangentLow.y; m1 = TangentLow.z; }
    if (g >= KnotX.y) { x0 = KnotX.y; x1 = KnotX.z; y0 = KnotY.y; y1 = KnotY.z; m0 = TangentLow.z; m1 = TangentHigh.x; }
    if (g >= KnotX.z) { x0 = KnotX.z; x1 = KnotX.w; y0 = KnotY.z; y1 = KnotY.w; m0 = TangentHigh.x; m1 = TangentHigh.y; }
    if (g >= KnotX.w) { x0 = KnotX.w; x1 = 1.0; y0 = KnotY.w; y1 = 1.0; m0 = TangentHigh.y; m1 = TangentHigh.z; }
    float h = x1 - x0;
    float t = saturate((g - x0) / h);
    float t2 = t * t;
    float t3 = t2 * t;
    // CPU 판(`apply_parametric_tone_curve`)과 같은 연산 순서입니다.
    float curved = (((2.0 * t3) - (3.0 * t2) + 1.0) * y0) + ((t3 - (2.0 * t2) + t) * h * m0) +
                   (((-2.0 * t3) + (3.0 * t2)) * y1) + ((t3 - t2) * h * m1);
    float target = SrgbEncodedToLinear(clamp(curved, 0.0, 1.0));
    Destination[coordinate] = float4(WithLuma(safeRgb, sourceLuma, target), source.a);
}
