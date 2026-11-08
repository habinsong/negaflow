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

// 검정 한 단계(|amount| ≤ 1). CPU `basic_tone_blacks` 와 같은 식입니다. 올리는 쪽은 smoothstep
// 0~0.03 상승, 내리는 쪽은 t − c·min(1, t/0.03)·fall 이고 0 아래는 0 에 붙습니다.
float BasicToneBlacks(float t, float amount) {
    float fall = 1.0 - smoothstep(0.14, 0.30, t);
    if (amount >= 0.0) {
        return t + (amount * 0.06 * smoothstep(0.0, 0.03, t) * fall);
    }
    return max(t + (amount * 0.06 * min(1.0, max(t, 0.0) / 0.03) * fall), 0.0);
}

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

    // 단계마다 앞 단계의 출력에 차례로 겁니다(macOS `basicTone`, CPU `apply_basic_tone`). 각 단계가
    // 그 자체로 단조라 합성도 단조입니다 — 어떤 슬라이더 조합에서도 톤이 뒤집히지 않습니다.
    // 농도: 미드톤(+ 가 어둡게). 미드(0.46) 중심 대역.
    float density = clamp(DensityAmount, -1.0, 1.0);
    target -= density * 0.10 * smoothstep(0.18, 0.36, target) * (1.0 - smoothstep(0.58, 0.76, target));

    // 명부: 올리면 밝아집니다(내리면 recovery).
    float highlights = clamp(HighlightAmount, -1.0, 1.0);
    target += highlights * 0.10 * smoothstep(0.55, 0.80, target);

    // 암부: 올리는 쪽은 0.02~0.08 상승(절대 검정 앵커), 내리는 쪽은 검정에서부터 0~0.20 상승.
    // 위쪽 경계 0.30~0.46(미드 전에 0).
    float shadows = clamp(ShadowAmount, -1.0, 1.0);
    float shadowRise = shadows > 0.0 ? smoothstep(0.02, 0.08, target) : smoothstep(0.0, 0.20, target);
    target += shadows * 0.10 * shadowRise * (1.0 - smoothstep(0.30, 0.46, target));

    // 백점. 범위는 `DevelopToneRange.whites` 의 ±2 이고 ±1 을 넘는 몫은 같은 단계를 한 번 더 겁니다.
    float whites = clamp(WhitesAmount, -2.0, 2.0);
    float whitesFirst = clamp(whites, -1.0, 1.0);
    target += whitesFirst * 0.12 * smoothstep(0.68, 0.92, target);
    target += (whites - whitesFirst) * 0.12 * smoothstep(0.68, 0.92, target);

    // 흑점: 순검정 바로 위 띠, y=0 앵커. 같은 이유로 ±1 씩 두 단계입니다.
    float blacks = clamp(BlacksAmount, -2.0, 2.0);
    float blacksFirst = clamp(blacks, -1.0, 1.0);
    target = BasicToneBlacks(target, blacksFirst);
    target = BasicToneBlacks(target, blacks - blacksFirst);

    float newLuma = SrgbEncodedToLinear(clamp(target, 0.0, 1.0));
    Destination[coordinate] = float4(WithLuma(safeRgb, sourceLuma, newLuma), source.a);
}
