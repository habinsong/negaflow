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

// 휘도 `luma` 를 고정한 채 chroma 를 몇 배까지 키울 수 있는지입니다. 가장 먼저 0 또는 1 에 닿는
// 채널이 정합니다. [0,1] 안의 화소는 1 이상을, 이미 밖에 나간 화소는 1 미만을 돌려줍니다.
// chroma 가 0 에 가까워 어느 배율로도 경계에 닿지 않으면 아주 큰 값입니다. 휘도 자체가 (0,1) 밖이면
// 0 입니다(호출 쪽은 "더 키우지 않음"으로 읽습니다).
// CPU `chroma_scale_headroom`(imaging/bounded_chroma_scale.h) · macOS `chromaScaleHeadroom` 과 같습니다.
// `ToneSafeUnitRGB` 는 같은 계산에 상한 1 을 씌운 것이라 따로 둡니다.
float ChromaScaleHeadroom(float luma, float3 chroma) {
    if (luma <= 0.0 || luma >= 1.0) {
        return 0.0;
    }
    float limit = 1.0e9;
    if (chroma.r > 1.0e-5) { limit = min(limit, (1.0 - luma) / chroma.r); }
    else if (chroma.r < -1.0e-5) { limit = min(limit, -luma / chroma.r); }
    if (chroma.g > 1.0e-5) { limit = min(limit, (1.0 - luma) / chroma.g); }
    else if (chroma.g < -1.0e-5) { limit = min(limit, -luma / chroma.g); }
    if (chroma.b > 1.0e-5) { limit = min(limit, (1.0 - luma) / chroma.b); }
    else if (chroma.b < -1.0e-5) { limit = min(limit, -luma / chroma.b); }
    return limit;
}

// 채도·색 깊이 배율의 끝 보호에서 경계까지 남은 배율 여유 중 선형으로 두는 비율입니다.
// CPU `bounded_chroma_knee_fraction` 과 같은 값이어야 합니다 — 한쪽만 바꾸면 두 경로의 결과가 갈립니다.
static const float BoundedChromaKneeFraction = 0.75;

// 실제로 곱할 chroma 배율입니다(CPU `bounded_chroma_scale`, macOS `chromaScaleBounded`).
// factor <= knee 는 그대로, 그 위는 limit 에 점근하는 지수 숄더이고 knee 에서 기울기 1 로 이어집니다.
// 이미 경계 밖인 화소(limit 1)는 더 키우지 않고, 줄이는 쪽(factor <= 1)은 손대지 않습니다.
float BoundedChromaScale(float factor, float luma, float3 chroma) {
    if (!(factor > 1.0)) {
        return factor;
    }
    float limit = max(ChromaScaleHeadroom(luma, chroma), 1.0);
    float knee = 1.0 + (BoundedChromaKneeFraction * (limit - 1.0));
    if (!(factor > knee)) {
        return factor;
    }
    float room = limit - knee;
    return room > 1.0e-6
        ? knee + (room * (1.0 - exp(-(factor - knee) / room)))
        : knee;
}

// `color/srgb_transfer.cpp`. 부호를 보존합니다 — 작업 이미지는 0 아래 값을 일부러 남깁니다.
// 휘도 목표를 화소에 싣습니다(CPU `with_luma`, macOS `withLuma`). 어둡게 할 때는 채널 비율을
// 보존하고, 밝힐 때는 같은 값을 더합니다. 더한 결과의 한 채널이 1 을 넘으면 그 채널만 자르지
// 않고, 목표 휘도를 지킨 채 chroma 만 1 에 맞게 줄입니다(채널별로 자르면 목표 휘도에 못 미치고
// 남은 채널의 비율이 깨져 색조가 돕니다). 입력 rgb 는 [0,1] 안이어야 합니다.
float3 WithLuma(float3 rgb, float luma, float newLuma) {
    if (newLuma < luma && luma > 1.0e-6) {
        return clamp(rgb * (newLuma / luma), 0.0, 1.0);
    }
    float3 lifted = rgb + (newLuma - luma);
    if (all(lifted <= float3(1.0, 1.0, 1.0))) {
        return clamp(lifted, 0.0, 1.0);
    }
    float3 chroma = rgb - float3(luma, luma, luma);  // 같은 값을 더해도 휘도 기준 chroma 는 변하지 않는다
    float fold = min(1.0, ChromaScaleHeadroom(newLuma, chroma));
    return clamp(float3(newLuma, newLuma, newLuma) + (chroma * fold), 0.0, 1.0);
}

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
