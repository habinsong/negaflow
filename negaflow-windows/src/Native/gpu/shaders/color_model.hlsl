// 컬러 모델(우측 인스펙터의 온도·틴트·색 깊이·vibrance·채도·원색)입니다.
//
// CPU 판 : `imaging/color_model.cpp` `apply_color_model` / `apply_pixel`
//
// ☠️ **순서를 바꾸지 마십시오.** 온도 → 틴트 → 색 깊이 → vibrance → 채도 → 원색 입니다.
//    전부 곱셈이라 순서가 바뀌면 값이 달라집니다.
//
// ☠️ **게이트를 그대로 옮겼습니다.** CPU 는 각 항목이 `identity_threshold`(1e-3) 이하이면
//    **아예 건너뜁니다.** 여기서도 그래야 합니다 — 돌리면 `1 + 0` 곱셈의 반올림이 붙습니다.
//    게이트 자체는 호스트가 판정해 플래그로 넘깁니다(화소마다 같은 값입니다).

#include "tone_shared.hlsli"
#include "vibrance_shared.hlsli"

cbuffer ColorModelConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    float Warmth;
    float Tint;
    float ColorDepth;
    float Vibrance;
    float Saturation;
    float RedPrimary;
    float GreenPrimary;
    float BluePrimary;
    // 호스트가 판정한 게이트. 비트 하나씩 씁니다:
    // 1=warmth 2=tint 4=colorDepth 8=vibrance 16=saturation 32=primaries
    uint Gates;
    uint VibranceLow;
    float VibranceBlend;
    float VibranceQuantum;
    // vibrance 커널이 받는 amount 는 슬라이더의 0.8배입니다(`color_model.cpp:81`).
    float VibranceAmount;
    float3 Padding1;
};

// `apply_saturation` 과 같습니다 — 앵커가 **Rec.709 휘도**입니다.
// (vibrance 의 앵커는 산술 평균이라 다릅니다. 섞지 마십시오.)
float3 ApplySaturation(float3 color, float factor) {
    float y = dot(color, LumaCoefficients);
    return y + ((color - y) * factor);
}

[numthreads(8, 8, 1)]
void ColorModelMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];
    float3 color = source.rgb;

    if ((Gates & 1u) != 0u) {
        color.r *= 1.0 + (Warmth * 0.18);
        color.g *= 1.0 + (Warmth * 0.03);
        color.b *= 1.0 - (Warmth * 0.18);
    }
    if ((Gates & 2u) != 0u) {
        float redBlue = 1.0 - (Tint * 0.12);
        color.r *= redBlue;
        color.g *= 1.0 + (Tint * 0.24);
        color.b *= redBlue;
    }
    if ((Gates & 4u) != 0u) {
        color = ApplySaturation(color, 1.0 + (ColorDepth * 0.35));
    }
    if ((Gates & 8u) != 0u) {
        color = ApplyMeasuredVibrance(
            color, VibranceAmount, VibranceLow, VibranceBlend, VibranceQuantum);
    }
    if ((Gates & 16u) != 0u) {
        color = ApplySaturation(color, 1.0 + (Saturation * 0.6));
    }
    if ((Gates & 32u) != 0u) {
        color.r *= 1.0 + (RedPrimary * 0.32);
        color.g *= 1.0 + (GreenPrimary * 0.32);
        color.b *= 1.0 + (BluePrimary * 0.32);
    }

    Destination[coordinate] = float4(color, source.a);
}
