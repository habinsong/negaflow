// 노출입니다. macOS 대응은 `exposureShoulder` Metal 커널(EV<=0 은 Core Image 곱셈),
// Windows CPU 판은 `core/pointwise.cpp` `apply_exposure` 이고, 이 셰이더는 그것과 화소값이
// 같아야 합니다.
//
// 입력은 반전의 인화 응답 출력(측정 최농부 0.70, 천장 0.90)이라 장면 선형이 아닙니다. 그 위에
// 2^EV 만 곱하면 숄더가 다시 펴져 0.515EV 만에 하드 클립되므로, + 쪽은 무릎(Knee) 위 휘도를
// 1.0 에 점근하는 지수 숄더로 접습니다(Blend 0 = 순수 곱). 클램프하지 마십시오 — [0,1] 밖
// 값은 뒤 단계와 출력 경계가 처리합니다.
//
// 배수는 CPU 가 `exp2(stops)` 로 미리 계산해 넘깁니다. 셰이더에서 다시 계산하면
// `exp2` 구현 차이가 곱셈마다 실리므로 CPU 가 준 값을 그대로 씁니다.

#include "tone_shared.hlsli"

cbuffer ExposureConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    float Multiplier;
    float Knee;
    float Blend;
    float Padding1;
};

[numthreads(8, 8, 1)]
void ExposureMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];
    float3 rgb = source.rgb * Multiplier;
    float luminance = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    if (Blend > 0.0 && luminance > Knee) {
        float room = 1.0 - Knee;
        float shoulder = 1.0 - room * exp(-(luminance - Knee) / room);
        rgb *= (luminance + (shoulder - luminance) * Blend) / luminance;
    }
    Destination[coordinate] = float4(rgb, source.a);
}
