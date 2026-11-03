// 스캐너 렌더링 — 장면과 무관한 고정 변환입니다.
//
// macOS : `ChromabaseMetalKernels+FilterSources.swift` `scannerRendering`
// CPU 판 : `imaging/scanner_target_rendering.cpp` `render_linear`
//
// 단조 3차 Hermite 의 값·기울기는 호스트(`rendering_setup`)가 만든 것을 그대로 받습니다.
// knot 위치는 세 곳(macOS 커널·CPU·이 셰이더)이 같은 상수입니다. 색 쪽 곡선은 knot 범위
// 밖에서 평평하고 톤 곡선만 끝 기울기로 연장합니다. CPU 는 double, 이것은 float 입니다.

#include "tone_shared.hlsli"

cbuffer ScannerRenderingConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    // 상수 버퍼 배열은 원소마다 16바이트라 float4 로 묶고 `[i>>2][i&3]` 로 읽습니다.
    float4 ToneYs[3];
    float4 ToneMs[3];
    float4 GainYs;
    float4 GainMs;
    float4 Crosstalk0;   // (R←G, R←B, G←R, G←B)
    float4 Crosstalk1;   // (B←R, B←G, strength, monochrome)
    float4 RedYs;        // (y0, y1, y2, _)
    float4 RedMs;
    float4 BlueYs;
    float4 BlueMs;
};

static const float ToneXs[11] = { -8.0, -6.0, -4.0, -3.0, -2.0, -1.0, 0.0, 1.0, 1.5, 2.0, 2.5 };
static const float GainXs[4] = { -5.0, -2.0, 0.0, 2.0 };
static const float BalanceXs[3] = { -4.0, -1.0, 2.0 };

float ToneY(int i) { return ToneYs[i >> 2][i & 3]; }
float ToneM(int i) { return ToneMs[i >> 2][i & 3]; }

float HermiteSegment(float x, float x0, float x1, float y0, float y1, float m0, float m1) {
    float h = x1 - x0;
    float t = (x - x0) / h;
    float t2 = t * t;
    float t3 = t2 * t;
    return ((2.0 * t3 - 3.0 * t2 + 1.0) * y0) + ((t3 - 2.0 * t2 + t) * h * m0) +
        ((-2.0 * t3 + 3.0 * t2) * y1) + ((t3 - t2) * h * m1);
}

float ToneCurve(float x) {
    if (x < ToneXs[0]) { return ToneY(0) + ToneM(0) * (x - ToneXs[0]); }
    if (x > ToneXs[10]) { return ToneY(10) + ToneM(10) * (x - ToneXs[10]); }
    int i = 0;
    [loop]
    while (i < 9 && x > ToneXs[i + 1]) { i++; }
    return HermiteSegment(x, ToneXs[i], ToneXs[i + 1], ToneY(i), ToneY(i + 1), ToneM(i), ToneM(i + 1));
}

float GainCurve(float x) {
    int i = 0;
    [unroll]
    for (int k = 0; k < 2; ++k) { if (x > GainXs[k + 1]) { i = k + 1; } }
    return HermiteSegment(x, GainXs[i], GainXs[i + 1], GainYs[i], GainYs[i + 1], GainMs[i], GainMs[i + 1]);
}

float BalanceCurve(float x, float4 ys, float4 ms) {
    int i = x > BalanceXs[1] ? 1 : 0;
    return HermiteSegment(x, BalanceXs[i], BalanceXs[i + 1], ys[i], ys[i + 1], ms[i], ms[i + 1]);
}

[numthreads(8, 8, 1)]
void ScannerRenderingMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    float4 src = Source[id.xy];
    bool monochrome = Crosstalk1.w > 0.5;
    float3 input = src.rgb;
    if (monochrome) {
        float gray = dot(input, LumaCoefficients);
        input = float3(gray, gray, gray);
    }
    float3 x = max(input, float3(1.0e-5, 1.0e-5, 1.0e-5));
    float lumaY = max(dot(x, LumaCoefficients), 1.0e-5);
    float stops = log2(lumaY / 0.18);
    float3 d = log2(x) - log2(lumaY);
    float3 mixed = float3(
        d.r + Crosstalk0.x * (d.g - d.r) + Crosstalk0.y * (d.b - d.r),
        d.g + Crosstalk0.z * (d.r - d.g) + Crosstalk0.w * (d.b - d.g),
        d.b + Crosstalk1.x * (d.r - d.b) + Crosstalk1.y * (d.g - d.b));
    if (!monochrome) {
        float balanceStops = clamp(stops, -4.0, 2.0);
        mixed.r += BalanceCurve(balanceStops, RedYs, RedMs);
        mixed.b += BalanceCurve(balanceStops, BlueYs, BlueMs);
    }
    float gain = clamp(GainCurve(clamp(stops, -5.0, 2.0)), 0.0, 2.0);
    float outY = SrgbEncodedToLinear(clamp(ToneCurve(stops), 0.0, 1.0));
    float3 ratio = exp2(gain * mixed);
    float3 o = ratio * (outY / max(dot(ratio, LumaCoefficients), 1.0e-6));
    float peak = max(o.r, max(o.g, o.b));
    if (peak > 1.0) {
        float t = clamp((1.0 - outY) / max(peak - outY, 1.0e-9), 0.0, 1.0);
        o = float3(outY, outY, outY) + (o - float3(outY, outY, outY)) * t;
    }
    o = max(o, float3(0.0, 0.0, 0.0));
    float strength = Crosstalk1.z;
    Destination[id.xy] = float4(input + (o - input) * strength, src.a);
}
