// 밀도 의존 그레인입니다. macOS `digitalFilmGrainDensity`(`ChromabaseMetalKernels.swift:800`),
// Windows CPU 판은 `imaging/digital_film_grain.cpp` `apply_digital_film_grain_material` 입니다.
//
// ☠️ **맞춰야 할 상대는 Apple 의 `CIRandomGenerator` 가 아니라 Windows CPU 필드입니다.**
//    macOS 는 `CIRandomGenerator` 출력을 노이즈로 받는데 그 수열은 비공개입니다
//    (공식 문서에 파라미터만 있고 알고리즘이 없습니다). 그래서 `digital_film_grain.h:41-44`
//    가 *"statistical, not pixel-exact"* 계약을 이미 적어 두었고, Windows 는 좌표 해시
//    필드를 씁니다 — 재시도·타일이 값을 흔들 수 없는 결정적 필드입니다.
//
// 해시는 **전부 uint32 정수 연산**이라 CPU 와 **비트 단위로 같아야 합니다.**
// 다르면 옮겨 적은 것이 틀린 것입니다.
//
// 보간 경로(`size > 1.01`)만 부동소수입니다. CPU 는 `source_x` 를 `double` 로 굴리지만
// (`digital_film_grain.cpp:53-56`) GPU 는 float 입니다. **쌍선형 보간이 연속이라** 격자
// 경계에서 `floor` 가 한 칸 밀려도 값이 튀지 않습니다 — 밀린 쪽의 가중치가 0/1 로
// 붙기 때문입니다. 남는 오차는 `tx` 의 양자화뿐이고, 실제 진폭(≤0.05)과 밀도 미분을
// 함께 놓으면 출력 오차는 1e-6 아래입니다. 시험이 그 값을 고정합니다.

#include "tone_shared.hlsli"

cbuffer DigitalFilmGrainConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    // `profile.amplitude * clamp(strength, 0, 1)` 을 CPU 가 float 로 내린 값입니다.
    // CPU 판도 화소 루프 안에서 `static_cast<float>(amplitude)` 를 곱합니다.
    float Amplitude;
    float ChromaRatio;
    float NoiseSize;
    float Padding1;
};

// `digital_film_grain.cpp:25-36`. 연산자 우선순위(`*` 가 `^` 보다 먼저)까지 같습니다.
uint CoordinateHash(uint x, uint y, uint channel) {
    uint value = x * 0x9e3779b9u ^ y * 0x85ebca6bu ^
                 channel * 0xc2b2ae35u ^ 0x27d4eb2fu;
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    value ^= value >> 16u;
    return value;
}

// `:38-44`. `>> 8` 뒤 값은 [0, 2^24−1] 이고 나누는 수도 2^24−1 이라 둘 다 float 로
// 정확히 표현됩니다 — 이 한 줄은 CPU 와 마지막 비트까지 같습니다.
float UnitNoise(uint x, uint y, uint channel) {
    return float(CoordinateHash(x, y, channel) >> 8u) / 16777215.0;
}

// `:46-68`.
float ScaledNoise(uint x, uint y, uint channel) {
    if (NoiseSize <= 1.01) {
        return UnitNoise(x, y, channel);
    }
    float sourceX = (float(x) + 0.5) / NoiseSize;
    float sourceY = (float(y) + 0.5) / NoiseSize;
    uint x0 = uint(floor(sourceX));
    uint y0 = uint(floor(sourceY));
    float tx = sourceX - float(x0);
    float ty = sourceY - float(y0);
    float n00 = UnitNoise(x0, y0, channel);
    float n10 = UnitNoise(x0 + 1u, y0, channel);
    float n01 = UnitNoise(x0, y0 + 1u, channel);
    float n11 = UnitNoise(x0 + 1u, y0 + 1u, channel);
    float top = n00 + (n10 - n00) * tx;
    float bottom = n01 + (n11 - n01) * tx;
    return top + (bottom - top) * ty;
}

// `:70-82`. 밀도 도메인에서 더합니다 — 필름 그레인은 가산 오버레이가 아니라 곱셈 변조라
// macOS 주석이 명시합니다. 여기서 도메인을 바꾸면 암부에서 수십 배로 보입니다.
float ApplyChannel(float source, float noise) {
    float value = max(source, 1.0e-5);
    float density = -log10(value / 0.18);
    float physical = sqrt(max(density, 0.0) + 0.02);
    float t = (density - 1.0) / 1.15;
    float perceptual = exp(-(t * t));
    float amount = Amplitude * physical * perceptual;
    return 0.18 * pow(10.0, -(density + noise * amount));
}

[numthreads(8, 8, 1)]
void DigitalFilmGrainMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];
    float3 noise = float3(
        ScaledNoise(id.x, id.y, 0u) - 0.5,
        ScaledNoise(id.x, id.y, 1u) - 0.5,
        ScaledNoise(id.x, id.y, 2u) - 0.5);
    // 채도 비율. 1 이면 채널이 따로 놀고 0 이면 휘도 노이즈만 남습니다.
    float luma = (noise.x + noise.y + noise.z) / 3.0;
    noise = luma + (noise - luma) * ChromaRatio;
    Destination[coordinate] = float4(
        ApplyChannel(source.r, noise.x),
        ApplyChannel(source.g, noise.y),
        ApplyChannel(source.b, noise.z),
        source.a);
}
