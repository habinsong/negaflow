// 포인트 커브입니다. macOS `PointCurveStage` 에 대응하고 Windows CPU 판은
// `imaging/point_curve.cpp` `apply_point_curves` 입니다.
//
// 커브 자체(단조 3차 보간으로 64샘플 LUT 를 만드는 부분)는 **CPU 가 합니다** —
// `build_point_curve_luts`. 화소마다 같은 값이라 GPU 로 옮길 이유가 없고, 옮기면 두 벌이 됩니다.
// 이 셰이더는 **만들어진 LUT 를 적용만** 합니다.
//
// 적용은 sRGB 부호화 도메인에서 합니다 — 선형광에서 곧바로 찍으면 커브 모양이 달라집니다.
//
// 주의 HLSL 상수 버퍼의 배열은 원소마다 16바이트를 차지합니다. 64샘플을 `float LUT[64]` 로 두면
// 1024바이트를 먹고 인덱싱도 어긋납니다. `float4[16]` 으로 묶어 `[i>>2][i&3]` 로 읽습니다.

#include "tone_shared.hlsli"

#define NEGAFLOW_POINT_CURVE_LUT_SIZE 64
#define NEGAFLOW_POINT_CURVE_VECTORS 16

cbuffer PointCurveConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    float4 RedLut[NEGAFLOW_POINT_CURVE_VECTORS];
    float4 GreenLut[NEGAFLOW_POINT_CURVE_VECTORS];
    float4 BlueLut[NEGAFLOW_POINT_CURVE_VECTORS];
};

// CPU 판 `sample_lut` 과 같은 선형 보간입니다.
float SampleCurve(float4 lut[NEGAFLOW_POINT_CURVE_VECTORS], float encoded) {
    float bounded = clamp(encoded, 0.0, 1.0);
    float position = bounded * float(NEGAFLOW_POINT_CURVE_LUT_SIZE - 1);
    int lower = int(position);
    int upper = min(lower + 1, NEGAFLOW_POINT_CURVE_LUT_SIZE - 1);
    float fraction = position - float(lower);
    float low = lut[lower >> 2][lower & 3];
    float high = lut[upper >> 2][upper & 3];
    return low + ((high - low) * fraction);
}

// CPU 판 `apply_lut_component` 과 같습니다.
float ApplyCurve(float4 lut[NEGAFLOW_POINT_CURVE_VECTORS], float linearValue) {
    float encoded = LinearToSrgbEncoded(linearValue);
    float mapped = SampleCurve(lut, encoded);
    return SrgbEncodedToLinear(mapped);
}

[numthreads(8, 8, 1)]
void PointCurveMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];
    Destination[coordinate] = float4(
        ApplyCurve(RedLut, source.r),
        ApplyCurve(GreenLut, source.g),
        ApplyCurve(BlueLut, source.b),
        source.a);
}
