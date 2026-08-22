// macOS `ChromabaseMetalKernels.swift:557` `[[stitchable]] float4 negativeInvert(...)`.
// Windows CPU 판은 `core/negative_inversion.cpp` `invert_channel` 이고, 이 셰이더는 그것과
// 화소값이 같아야 합니다(동치 시험 허용 오차 1e-5).
//
// CPU 판 주석 원문 — *"On a 16 MP scan this is the most expensive stage in the whole develop,
// almost entirely transcendentals."* 초월함수(log10/pow/exp)가 화소마다 채널별로 도는 자리라
// GPU 이득이 가장 큰 커널입니다.
//
// 주의 CPU 판은 화소마다 결과가 유한한지 보고 아니면 `non_finite_output` 으로 **전체를 실패**
// 시킵니다. 이 셰이더에는 그 경로가 없습니다 — 화소별 실패를 올리려면 UAV 카운터가
// 따로 필요합니다. 호출부는 CPU 쪽 `validate_parameters` 관문을 **그대로 유지**해야 합니다
// (dmin>0 · dmax>0 · response 유한). 이 제한은 docs/audit 에 적어 두었습니다.

#include "tone_shared.hlsli"

cbuffer NegativeInvertConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    float3 Dmin; // 채널별 베이스 투과율
    float ResponseYCeiling;
    float3 DmaxNormalized; // 채널별 측정/프리셋/명목 밀도 범위
    float ResponseAmplitude;
    float ResponseRate;
    float ResponseShape;
    float2 Padding1;
};

[numthreads(8, 8, 1)]
void NegativeInvertMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];

    // CPU 판 `invert_channel` 을 채널 셋에 한꺼번에 적용합니다. 채널 사이에 의존이 없습니다.
    float3 boundedTransmission = max(source.rgb, 1e-5);
    float3 density = log10(Dmin / boundedTransmission) / max(DmaxNormalized, 1e-6);
    // `pow(0, shape)` 는 NaN 위험이라 CPU 와 같이 하한 1e-12 로 같은 극한값을 보장합니다.
    float3 argument = pow(max(ResponseRate * abs(density), 1e-12), ResponseShape);
    float3 y = ResponseYCeiling - (ResponseAmplitude * exp(-argument));
    float toeY = ResponseYCeiling - ResponseAmplitude;
    float3 mirrored = (2.0 * toeY) - y;
    float3 outputY = density >= 0.0 ? y : mirrored;

    Destination[coordinate] = float4(pow(10.0, outputY), source.a);
}
