// 분리형 가우시안입니다. macOS 는 `CIGaussianBlur`(Apple 내장)를 네 곳에서 씁니다 —
// `ColorModel.swift:128,166` · `FilmScanDenoise.swift:96` · `LocalDodgeBurnStage.swift:169` ·
// `ScannerNoiseReduction+Color.swift:19`. Windows 에는 그 내장 필터가 없어 **우리가 만듭니다.**
//
// Windows CPU 판은 두 곳에 있고 **수식과 누적 순서가 같습니다**:
//   `imaging/film_scan_denoise_filters.cpp:13` `gaussian_blur`      (Rgb, 가장자리 클램프)
//   `imaging/texture_stage_gaussian.h:22`      `gaussian_transform` (Rgba, 세 가지 가장자리)
//
// ☠️ **가중치를 셰이더에서 만들지 마십시오.** 호스트가 CPU 와 **같은 코드로** 계산해
//    넘깁니다(`GpuGaussianBlur::create_weights`). `exp` 는 CPU 와 GPU 의 구현이 달라
//    마지막 비트가 갈리고, 그 차이가 전 화소에 곱해집니다. 실제로 값을 옮기는 것은
//    `coreimage_gaussian_effective_sigma` 의 분산 보정 0.08 이며 그것도 호스트 상수입니다.
//
// ☠️ **누적 순서를 바꾸지 마십시오.** CPU 는 `value = value + sample * weight` 를
//    offset `-R`→`+R` 로 돕니다. `/fp:precise` 의 MSVC 는 FMA 를 만들지 않으므로 곱과 합이
//    따로 반올림됩니다. HLSL 은 `precise` 로 fxc 의 FMA 축약을 막아 같게 둡니다.
//
// 박스 블러와 달리 러닝 섬이 아니라 화소마다 독립이므로 **2D 8×8 그룹**을 씁니다.

Texture2D<float4> Source : register(t0);
StructuredBuffer<float> Weights : register(t1);
RWTexture2D<float4> Destination : register(u0);

// ☠️ 앞 16바이트는 화소별 커널과 같은 `GpuPointwiseExtent` 자리입니다 — `uint2` 뒤의
//    `float2` 를 빼면 뒤 필드가 8바이트 앞에서 읽혀 조용히 틀린 값이 들어옵니다.
cbuffer GaussianConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    // 지원 반경. 탭 수는 `Radius * 2 + 1` 이고 `Weights` 의 길이와 같아야 합니다.
    int Radius;
    // 0 = clamp, 1 = mirror, 2 = transparent. `GaussianEdgeMode`(texture_stage_math.h:29) 와
    // 같은 순서입니다.
    int EdgeMode;
    // 1 이면 알파도 함께 흐립니다(`texture_stage` 의 `FilterSample.alpha`).
    // 0 이면 CPU `film_scan_denoise` 의 `Rgb` 경로와 같이 원본 알파를 그대로 둡니다.
    int BlurAlpha;
    float Padding1;
};

#define NEGAFLOW_GAUSSIAN_EDGE_CLAMP 0
#define NEGAFLOW_GAUSSIAN_EDGE_MIRROR 1
#define NEGAFLOW_GAUSSIAN_EDGE_TRANSPARENT 2

// `texture_stage_gaussian.h:43-52` 의 `coordinate` 람다를 그대로 옮긴 것입니다.
// Core Image 는 경계 화소 자신을 접습니다 — `-1 → 0`, `limit → limit - 1`.
int fold_coordinate(int candidate, int limit) {
    if (EdgeMode != NEGAFLOW_GAUSSIAN_EDGE_MIRROR || limit <= 1) {
        return clamp(candidate, 0, limit - 1);
    }
    int period = limit * 2;
    // CPU 는 `candidate % period` 뒤에 음수면 `period` 를 더합니다 — 합치면 유클리드
    // 나머지입니다. fxc 는 `/WX` 아래에서 **부호 있는 `%` 를 거부**하므로(X3556) 먼저
    // 주기의 배수만큼 밀어 올려 부호 없는 나머지로 같은 값을 냅니다. 주기의 배수를 더하는
    // 것은 나머지를 바꾸지 않습니다.
    //
    // `candidate >= position - Radius >= -Radius` 이고 `period >= 2`(위에서 `limit > 1`)
    // 이므로 `period * Radius` 면 항상 음수가 아니게 됩니다.
    uint folded = uint(candidate + (period * Radius)) % uint(period);
    return folded < uint(limit) ? int(folded) : (period - 1 - int(folded));
}

// 한 축을 훑습니다. `horizontal` 이 참이면 x 를, 거짓이면 y 를 움직입니다.
// 두 패스가 같은 코드를 쓰도록 묶어 둡니다 — 따로 두면 한쪽만 고치는 사고가 납니다.
precise float4 blur_axis(uint2 coordinate, bool horizontal) {
    int limit = horizontal ? int(Extent.x) : int(Extent.y);
    int position = horizontal ? int(coordinate.x) : int(coordinate.y);

    precise float4 value = float4(0.0, 0.0, 0.0, 0.0);
    for (int offset = -Radius; offset <= Radius; ++offset) {
        int candidate = position + offset;
        if (EdgeMode == NEGAFLOW_GAUSSIAN_EDGE_TRANSPARENT &&
            (candidate < 0 || candidate >= limit)) {
            // CPU 의 `continue` 와 같습니다 — 더하지 않습니다(0 을 더하는 것과 다릅니다:
            // 가중치 합이 줄어 가장자리가 어두워지는 것이 Core Image 의 동작입니다).
            continue;
        }
        int folded = fold_coordinate(candidate, limit);
        uint2 sampleAt = horizontal ? uint2(uint(folded), coordinate.y)
                                    : uint2(coordinate.x, uint(folded));
        float4 sample = Source[sampleAt];
        value = value + (sample * Weights[uint(offset + Radius)]);
    }
    return value;
}

[numthreads(8, 8, 1)]
void GaussianHorizontalMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    precise float4 blurred = blur_axis(coordinate, true);
    Destination[coordinate] =
        BlurAlpha != 0 ? blurred : float4(blurred.rgb, Source[coordinate].a);
}

[numthreads(8, 8, 1)]
void GaussianVerticalMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    precise float4 blurred = blur_axis(coordinate, false);
    Destination[coordinate] =
        BlurAlpha != 0 ? blurred : float4(blurred.rgb, Source[coordinate].a);
}
