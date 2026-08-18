// macOS `ChromabaseMetalKernels.swift:185` `[[stitchable]] float4 basicTone(...)` 를 옮긴 것입니다.
// Windows CPU 판은 `imaging/tone_mapping.cpp:79` `apply_basic_tone` 이고, 이 셰이더는 그것과
// 화소값이 같아야 합니다(동치 시험 허용 오차 1e-5).
//
// 상수·마스크 경계·연산 순서를 바꾸지 마십시오. 하나라도 다르면 macOS 와 결과가 갈립니다.
//
// 2026-08-18: whites/blacks 의 ±2 clamp 를 macOS 와 맞춰 CPU·GPU 양쪽에 넣었습니다.
//    같이 고친 것 — `maximum_endpoint_tone_control = 2.0F`. 그 전 Windows 는 두 값을 ±1 로
//    막아 macOS 에서 되는 조작이 여기서는 요청 자체가 거부되었습니다.


#include "tone_shared.hlsli"


cbuffer BasicToneConstants : register(b0) {
    uint2 Extent;         // x = width, y = height
    float2 Padding0;
    float ContrastAmount;
    float DensityAmount;
    float HighlightAmount;
    float ShadowAmount;
    float WhitesAmount;
    float BlacksAmount;
    float2 Padding1;
};

[numthreads(8, 8, 1)]
void BasicToneMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];

    float3 safeRgb = ToneSafeUnitRGB(source.rgb);
    float sourceLuma = dot(safeRgb, LumaCoefficients);
    float encodedLuma = LinearToSrgbEncoded(clamp(sourceLuma, 0.0, 1.0));
    float target = encodedLuma;

    // 대비: photometric 미드(sRGB 0.46) 피벗의 파워 대비 — 끝점(0/1)·피벗 고정.
    // 음수는 지수<1 이 검정 부근을 들어올리므로 저역 가드(smoothstep 0.12~0.30)로
    // 절대 검정~딥섀도를 원본에 앵커합니다. Contrast −1 이 검정을 회색으로 띄우면 안 됩니다.
    float contrast = clamp(ContrastAmount, -1.0, 1.0);
    if (abs(contrast) > 1e-4) {
        const float pivot = 0.46;
        float exponent = pow(2.0, contrast * (contrast > 0.0 ? 0.9 : 0.7));
        // 이 자리의 `target` 은 바로 위에서 `LinearToSrgbEncoded(clamp(sourceLuma, 0, 1))` 로
        // 만든 값이라 항상 [0,1] 이고, 대비는 target 을 건드리는 첫 단계입니다.
        // 따라서 두 밑은 모두 0 이상이며 `max(…, 0)` 은 실제 정의역에서 **아무 값도 바꾸지
        // 않습니다.** fxc 가 pow 의 음수 밑을 경고(X3571)하므로 그 불변식을 코드로 적어 둡니다.
        // CPU 판(`std::pow`)도 같은 정의역을 전제합니다.
        float lowBase = max(target / pivot, 0.0);
        float highBase = max((1.0 - target) / (1.0 - pivot), 0.0);
        float curved = target < pivot
            ? pivot * pow(lowBase, exponent)
            : 1.0 - ((1.0 - pivot) * pow(highBase, exponent));
        float blend = contrast > 0.0 ? 1.0 : smoothstep(0.12, 0.30, target);
        // CPU 판이 `target += (curved - target) * blend` 로 씁니다. mix 와 같은 값이지만
        // 연산 순서를 CPU 와 맞춰 둡니다.
        target += (curved - target) * blend;
    }

    // 농도: 미드톤(+ 가 어둡게). 미드(0.46) 중심 대역.
    float midMask = smoothstep(0.18, 0.36, encodedLuma) * (1.0 - smoothstep(0.58, 0.76, encodedLuma));
    target -= DensityAmount * 0.10 * midMask;

    // 명부: 올리면 밝아집니다(내리면 recovery).
    float highlightMask = smoothstep(0.55, 0.80, encodedLuma);
    target += HighlightAmount * 0.10 * highlightMask;

    // 암부: 가시 암부를 들어올리되 절대 검정(<0.02)은 앵커, 미드(0.46) 전에 0 으로 테이퍼.
    float shadowMask = smoothstep(0.02, 0.08, encodedLuma) * (1.0 - smoothstep(0.32, 0.46, encodedLuma));
    target += ShadowAmount * 0.10 * shadowMask;

    // 백점. macOS 는 커널 안에서 ±2 로 clamp 합니다(`ChromabaseMetalKernels.swift:231`).
    // 범위는 `DevelopToneRange.whites` 의 `-2...2` 이고 계수 0.12 와 마스크는 그대로 둡니다.
    float whiteMask = smoothstep(0.68, 0.92, encodedLuma);
    target += clamp(WhitesAmount, -2.0, 2.0) * 0.12 * whiteMask;

    // 흑점: 순검정 바로 위 띠, y=0 앵커. 같은 이유로 ±2 clamp(`:235`).
    float blackMask = smoothstep(0.0, 0.03, encodedLuma) * (1.0 - smoothstep(0.14, 0.30, encodedLuma));
    target += clamp(BlacksAmount, -2.0, 2.0) * 0.06 * blackMask;

    float newLuma = SrgbEncodedToLinear(clamp(target, 0.0, 1.0));
    float delta = newLuma - sourceLuma;
    Destination[coordinate] = float4(
        clamp(safeRgb.r + delta, 0.0, 1.0),
        clamp(safeRgb.g + delta, 0.0, 1.0),
        clamp(safeRgb.b + delta, 0.0, 1.0),
        source.a);
}
