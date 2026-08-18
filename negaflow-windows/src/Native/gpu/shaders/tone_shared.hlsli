#ifndef NEGAFLOW_TONE_SHARED_HLSLI
#define NEGAFLOW_TONE_SHARED_HLSLI

// 화소별 커널이 공유하는 조각입니다. macOS 도 같은 인라인 함수를 커널들이 나눠 씁니다
// (`ChromabaseMetalKernels.swift` 상단의 `rgb2hsl`/`hsl2rgb`/`toneSafeUnitRGB`).
//
// 커널마다 복사하면 32벌이 되고, 한 벌만 고쳐도 조용히 갈라집니다.

// 모든 화소별 셰이더의 슬롯 배치입니다. 바꾸려면 `gpu_pointwise.cpp` 의 바인딩도 같이 바꾸십시오.
Texture2D<float4> Source : register(t0);
RWTexture2D<float4> Destination : register(u0);

static const float3 LumaCoefficients = float3(0.2126, 0.7152, 0.0722);

// `imaging/display_gamut_map.h` `tone_safe_unit_rgb` / macOS `toneSafeUnitRGB`.
// 채널별로 자르면 먼저 클리핑되는 채널이 색상을 끌고 갑니다. 루마를 잡고 채도만 양보시킵니다.
float3 ToneSafeUnitRGB(float3 rgb) {
    float y = clamp(dot(rgb, LumaCoefficients), 0.0, 1.0);
    float3 chroma = rgb - float3(y, y, y);
    float tr = chroma.r > 1e-5 ? (1.0 - y) / chroma.r : (chroma.r < -1e-5 ? (-y) / chroma.r : 1.0);
    float tg = chroma.g > 1e-5 ? (1.0 - y) / chroma.g : (chroma.g < -1e-5 ? (-y) / chroma.g : 1.0);
    float tb = chroma.b > 1e-5 ? (1.0 - y) / chroma.b : (chroma.b < -1e-5 ? (-y) / chroma.b : 1.0);
    float t = clamp(min(1.0, min(tr, min(tg, tb))), 0.0, 1.0);
    return clamp(float3(y, y, y) + (t * chroma), 0.0, 1.0);
}

// `color/srgb_transfer.cpp`. 부호를 보존합니다 — 작업 이미지는 0 아래 값을 일부러 남깁니다.
float LinearToSrgbEncoded(float linearValue) {
    float magnitude = abs(linearValue);
    if (magnitude <= 0.0031308) {
        return linearValue * 12.92;
    }
    float encoded = (1.055 * pow(magnitude, 1.0 / 2.4)) - 0.055;
    return linearValue < 0.0 ? -encoded : encoded;
}

float SrgbEncodedToLinear(float encoded) {
    float magnitude = abs(encoded);
    if (magnitude <= 0.04045) {
        return encoded / 12.92;
    }
    float linearValue = pow((magnitude + 0.055) / 1.055, 2.4);
    return encoded < 0.0 ? -linearValue : linearValue;
}

// HLSL 내장 smoothstep 은 `t=saturate((x-a)/(b-a)); t*t*(3-2t)` 로 CPU 판과 같은 식입니다.
// CPU 판의 `edge_low == edge_high` 특례는 이 커널들의 경계값에 해당이 없습니다.

#endif  // NEGAFLOW_TONE_SHARED_HLSLI
