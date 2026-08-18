#ifndef NEGAFLOW_FILM_SCAN_SHARED_HLSLI
#define NEGAFLOW_FILM_SCAN_SHARED_HLSLI

// `imaging/film_scan_denoise_math.h` 의 화소 산술을 그대로 옮긴 것입니다.
//
// ☠️ **HLSL 내장 `smoothstep`·`length`·`lerp`·`dot` 를 쓰지 마십시오.**
//    수식은 같아 보여도 fxc 가 `dp3`·`mad` 로 묶어 **결합 순서와 반올림이 달라집니다.**
//    CPU 는 `/fp:precise` 라 곱과 합이 따로 반올림되고, 그 차이가 뒤의 `1/(x+eps)` 나
//    `pow(x, 2.22)` 를 지나며 커집니다. 아래 함수들은 CPU 의 괄호를 그대로 지킵니다.

// `film_scan_denoise_math.h:37` `clamp_unit`.
precise float negaflow_clamp_unit(float value) {
    return clamp(value, 0.0, 1.0);
}

precise float3 negaflow_clamp_unit3(float3 value) {
    return float3(
        negaflow_clamp_unit(value.r),
        negaflow_clamp_unit(value.g),
        negaflow_clamp_unit(value.b));
}

// `film_scan_denoise_math.h:92` `smoothstep`.
//   const float t = clamp_unit((value - edge0) / (edge1 - edge0));
//   return t * t * (3.0F - 2.0F * t);
precise float negaflow_smoothstep(float edge0, float edge1, float value) {
    precise float t = negaflow_clamp_unit((value - edge0) / (edge1 - edge0));
    return (t * t) * (3.0 - (2.0 * t));
}

// `film_scan_denoise_math.h:73` `luminance`.
//   value.red * 0.2126F + value.green * 0.7152F + value.blue * 0.0722F
// C++ 은 왼쪽부터 묶으므로 `((r*a) + (g*b)) + (b*c)` 입니다. `dot` 은 이 순서를 지키지 않습니다.
precise float negaflow_luminance(float3 value) {
    return ((value.r * 0.2126) + (value.g * 0.7152)) + (value.b * 0.0722);
}

// `film_scan_denoise_math.h:78` `chroma`.
precise float3 negaflow_chroma(float3 value, float luma) {
    return float3(value.r - luma, value.g - luma, value.b - luma);
}

// `film_scan_denoise_math.h:86` `length`.
//   std::sqrt(r*r + g*g + b*b)  →  sqrt(((r*r) + (g*g)) + (b*b))
precise float negaflow_length(float3 value) {
    return sqrt((((value.r * value.r) + (value.g * value.g)) + (value.b * value.b)));
}

// `film_scan_denoise_math.h:100` `mix`.
//   first + (second - first) * weight
precise float negaflow_mix(float first, float second, float weight) {
    return first + ((second - first) * weight);
}

precise float3 negaflow_mix3(float3 first, float3 second, float weight) {
    return float3(
        negaflow_mix(first.r, second.r, weight),
        negaflow_mix(first.g, second.g, weight),
        negaflow_mix(first.b, second.b, weight));
}

#endif  // NEGAFLOW_FILM_SCAN_SHARED_HLSLI
