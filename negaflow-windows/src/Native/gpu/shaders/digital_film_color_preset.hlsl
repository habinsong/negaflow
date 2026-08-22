// 디지털 원본 전용 스톡 색 프리셋의 도메인 왕복입니다.
//
// macOS : `digitalToDisplayGamma`(`:738`) · `digitalToLinearLight`(`:742`) 와
// `DigitalFilmColorPresetStage.swift` 의 `CIMix`
// CPU 판 : `imaging/digital_film_color_preset.cpp` `apply_digital_film_color_preset`
//
// 색 조정 셋(믹서·그레이딩·캘리브레이션)은 **표시 도메인 0…1 을 전제로** 만들어졌습니다.
// 작업 이미지는 선형광이므로 감마를 씌워 들어갔다가 되돌립니다. 그 셋은 이미 GPU 커널이
// 있으므로(`color_mixer.hlsl`·`color_grade.hlsl`·`primary_calibration.hlsl`) 여기서
// 만드는 것은 **도메인 왕복과 강도 혼합** 둘뿐입니다.
//
// **`tone_shared.hlsli` 의 `LinearToSrgbEncoded` 를 쓰지 마십시오.** 그것은 부호를
// 보존합니다(작업 이미지가 0 아래 값을 일부러 남기기 때문). 이 자리의 CPU 판
// (`digital_film_color_preset.cpp:31-40`)과 macOS `digitalLinearToSRGB` 는 **부호를
// 보존하지 않고** 음수를 `value * 12.92` 로 그대로 통과시킵니다. 둘을 섞으면
// 음수 화소에서 값이 갈립니다.

#include "tone_shared.hlsli"

// 원본(선형광). 마지막 혼합에서 되돌아올 자리입니다.
Texture2D<float4> Original : register(t1);

cbuffer DigitalFilmColorPresetConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    float Strength;
    float3 Padding1;
};

// `digital_film_color_preset.cpp:31-35`.
float DigitalLinearToSrgb(float value) {
    return value <= 0.0031308
        ? value * 12.92
        : 1.055 * pow(max(value, 0.0), 1.0 / 2.4) - 0.055;
}

// `:37-41`.
float DigitalSrgbToLinear(float value) {
    return value <= 0.04045
        ? value / 12.92
        : pow(max((value + 0.055) / 1.055, 0.0), 2.4);
}

[numthreads(8, 8, 1)]
void DigitalGammaEncodeMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];
    Destination[coordinate] = float4(
        DigitalLinearToSrgb(source.r),
        DigitalLinearToSrgb(source.g),
        DigitalLinearToSrgb(source.b),
        source.a);
}

// 되돌리기와 강도 혼합을 한 번에 합니다. CPU 판도 같은 루프 안에서 둘을 합니다
// (`:135-149`) — 나누면 전 화소를 한 번 더 훑게 됩니다.
[numthreads(8, 8, 1)]
void DigitalGammaDecodeMixMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 graded = Source[coordinate];
    float3 original = Original[coordinate].rgb;
    float3 rendered = float3(
        DigitalSrgbToLinear(graded.r),
        DigitalSrgbToLinear(graded.g),
        DigitalSrgbToLinear(graded.b));
    Destination[coordinate] = float4(
        original + (rendered - original) * Strength,
        graded.a);
}
