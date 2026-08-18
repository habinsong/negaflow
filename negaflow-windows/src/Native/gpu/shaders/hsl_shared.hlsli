#ifndef NEGAFLOW_HSL_SHARED_HLSLI
#define NEGAFLOW_HSL_SHARED_HLSLI

// HSL 변환입니다. macOS 는 `ChromabaseMetalKernels.swift:29-60` 의 `rgb2hsl`/`hue2rgb`/`hsl2rgb`
// 를 커널들이 나눠 쓰고, Windows CPU 는 `imaging/color_mixer.cpp` 의 같은 함수를 씁니다.
//
// 이 파일은 **Windows CPU 판과 값이 같아야** 합니다. 두 판의 유일한 차이는
// `chroma_epsilon` 비교 방향입니다 — macOS 는 `d > 1e-5`, Windows 는 `difference <= 1e-5` 로
// 조기 반환합니다. 같은 뜻이고 경계값에서도 같은 가지를 탑니다.

static const float NegaflowChromaEpsilon = 1e-5;

float3 NegaflowRgbToHsl(float3 color) {
    float maximum = max(color.r, max(color.g, color.b));
    float minimum = min(color.r, min(color.g, color.b));
    float lightness = (maximum + minimum) * 0.5;
    float difference = maximum - minimum;

    if (difference <= NegaflowChromaEpsilon) {
        return float3(0.0, 0.0, lightness);
    }

    float saturation = lightness > 0.5
        ? difference / (2.0 - maximum - minimum)
        : difference / (maximum + minimum);

    float hue;
    if (maximum == color.r) {
        hue = (color.g - color.b) / difference;
        if (color.g < color.b) {
            hue += 6.0;
        }
    } else if (maximum == color.g) {
        hue = ((color.b - color.r) / difference) + 2.0;
    } else {
        hue = ((color.r - color.g) / difference) + 4.0;
    }
    hue /= 6.0;
    return float3(hue, saturation, lightness);
}

float NegaflowHueToRgb(float lower, float upper, float hue) {
    if (hue < 0.0) {
        hue += 1.0;
    }
    if (hue > 1.0) {
        hue -= 1.0;
    }
    if (hue < (1.0 / 6.0)) {
        return lower + ((upper - lower) * 6.0 * hue);
    }
    if (hue < 0.5) {
        return upper;
    }
    if (hue < (2.0 / 3.0)) {
        return lower + ((upper - lower) * ((2.0 / 3.0) - hue) * 6.0);
    }
    return lower;
}

float3 NegaflowHslToRgb(float3 hsl) {
    float hue = hsl.x;
    float saturation = hsl.y;
    float lightness = hsl.z;
    if (saturation < NegaflowChromaEpsilon) {
        return float3(lightness, lightness, lightness);
    }
    float upper = lightness < 0.5
        ? lightness * (1.0 + saturation)
        : lightness + saturation - (lightness * saturation);
    float lower = (2.0 * lightness) - upper;
    return float3(
        NegaflowHueToRgb(lower, upper, hue + (1.0 / 3.0)),
        NegaflowHueToRgb(lower, upper, hue),
        NegaflowHueToRgb(lower, upper, hue - (1.0 / 3.0)));
}

#endif  // NEGAFLOW_HSL_SHARED_HLSLI
