// 부분 대비 세 커널입니다. CPU 판은 `imaging/detail_enhancement.cpp` `apply_local_contrast`,
// macOS 는 `DetailEnhancement.localContrast` + `detailLocalContrast` 입니다.
//
//   Guide        원본 → 축소 평면(factor×factor 칸 평균 감마 휘도와 그 제곱)
//   Coefficients 흐린 평면 → 가이디드 필터 계수 a·b(축소 해상도)
//   Apply        원본 + 흐린 계수 → 결과
//
// 축소 평면의 가우시안은 `gaussian_blur.hlsl` 이 CPU 와 같은 가중치·같은 누적 순서로 합니다.
// 여기서도 **CPU 의 괄호를 그대로** 둡니다 — `precise` 로 fxc 의 곱셈-덧셈 축약을 막습니다
// (MSVC `/fp:precise` 도 축약하지 않습니다). 감마 변환의 `pow` 와 `tanh` 는 D3D11 이 정밀도를
// 느슨하게 허용하므로 CPU 와 마지막 비트까지 같지는 않습니다.

#include "tone_shared.hlsli"

Texture2D<float4> Coefficients : register(t1);

cbuffer LocalContrastConstants : register(b0) {
    uint2 Extent;
    uint2 LowExtent;
    uint Factor;
    float InverseFactor;
    float Epsilon;
    float Amount;
    float Halo;
    float3 Padding;
};

// CPU `luminance`(texture_stage_math.h) 와 같은 괄호입니다.
precise float Luminance(float3 rgb) {
    return ((rgb.r * 0.2126) + (rgb.g * 0.7152)) + (rgb.b * 0.0722);
}

[numthreads(8, 8, 1)]
void LocalContrastGuideMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= LowExtent.x || id.y >= LowExtent.y) {
        return;
    }
    uint top = id.y * Factor;
    uint bottom = min(Extent.y, top + Factor);
    uint left = id.x * Factor;
    uint right = min(Extent.x, left + Factor);
    // CPU 와 같은 순서(행 → 열)로 더합니다.
    precise float sum = 0.0;
    uint count = 0u;
    for (uint y = top; y < bottom; ++y) {
        for (uint x = left; x < right; ++x) {
            sum = sum + LinearToSrgbEncoded(clamp(Luminance(Source[uint2(x, y)].rgb), 0.0, 1.0));
            ++count;
        }
    }
    precise float mean = count > 0u ? sum / float(count) : 0.0;
    Destination[id.xy] = float4(mean, mean * mean, 0.0, 1.0);
}

// 입력은 흐린 축소 평면입니다 — `.r` 이 안내 평균, `.g` 가 제곱 평균.
[numthreads(8, 8, 1)]
void LocalContrastCoefficientsMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= LowExtent.x || id.y >= LowExtent.y) {
        return;
    }
    float4 means = Source[id.xy];
    precise float variance = max(means.g - (means.r * means.r), 0.0);
    precise float a = variance / (variance + Epsilon);
    precise float b = means.r - (a * means.r);
    Destination[id.xy] = float4(a, b, 0.0, 1.0);
}

// CPU `bilinear` — 원본 화소 중심 (x+0.5) 은 축소 좌표 (x+0.5)/factor − 0.5 에 놓입니다.
precise float2 BilinearCoefficients(float u, float v) {
    float cu = clamp(u, 0.0, float(LowExtent.x - 1u));
    float cv = clamp(v, 0.0, float(LowExtent.y - 1u));
    uint x0 = uint(cu);
    uint y0 = uint(cv);
    uint x1 = min(x0 + 1u, LowExtent.x - 1u);
    uint y1 = min(y0 + 1u, LowExtent.y - 1u);
    float fx = cu - float(x0);
    float fy = cv - float(y0);
    float2 top = (Coefficients[uint2(x0, y0)].rg * (1.0 - fx)) + (Coefficients[uint2(x1, y0)].rg * fx);
    float2 bottom = (Coefficients[uint2(x0, y1)].rg * (1.0 - fx)) + (Coefficients[uint2(x1, y1)].rg * fx);
    return (top * (1.0 - fy)) + (bottom * fy);
}

[numthreads(8, 8, 1)]
void LocalContrastApplyMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    float4 source = Source[id.xy];
    precise float luma = Luminance(source.rgb);
    if (luma <= 1.0e-5) {
        Destination[id.xy] = source;
        return;
    }
    precise float u = ((float(id.x) + 0.5) * InverseFactor) - 0.5;
    precise float v = ((float(id.y) + 0.5) * InverseFactor) - 0.5;
    precise float2 coefficient = BilinearCoefficients(u, v);
    precise float encoded = LinearToSrgbEncoded(luma);
    precise float g = clamp(encoded, 0.0, 1.0);
    precise float baseValue = clamp((coefficient.x * g) + coefficient.y, 0.0, 1.0);
    precise float weight = clamp((4.0 * g) * (1.0 - g), 0.0, 1.0);
    // a 는 그 자리가 경계인 정도입니다 — (1−a) 로 큰 경계 둘레(가이디드 필터 헤일로)를 걷어 냅니다.
    precise float textureWeight = 1.0 - clamp(coefficient.x, 0.0, 1.0);
    precise float lift = Halo * tanh((((Amount * weight) * textureWeight) * (g - baseValue)) / Halo);
    // CPU `with_lift` — 원 휘도의 45% 와 ≈2/255 아래로는 내리지 않습니다.
    precise float floorValue = max(encoded * 0.45, min(encoded, 0.008));
    precise float targetValue = max(encoded + lift, floorValue);
    precise float scale = SrgbEncodedToLinear(targetValue) / luma;
    Destination[id.xy] = float4(source.rgb * scale, source.a);
}
