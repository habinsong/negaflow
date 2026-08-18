// 노출입니다. macOS 는 이것을 `[[stitchable]]` 커널로 두지 않고 Core Image 의 곱셈으로
// 처리하므로 대응 Metal 커널이 없습니다. Windows CPU 판은 `core/pointwise.cpp` `apply_exposure`
// 이고, 이 셰이더는 그것과 화소값이 같아야 합니다.
//
// **장면 선형(scene-linear)** 이라 [0,1] 밖 값이 정상입니다. 클램프하지 마십시오 —
// CPU 판도 클램프하지 않습니다. 하이라이트 여유가 여기서 죽으면 뒤 단계가 전부 틀어집니다.
//
// 배수는 CPU 가 `exp2(stops)` 로 미리 계산해 넘깁니다. 셰이더에서 다시 계산하면
// `exp2` 구현 차이가 곱셈마다 실리므로 CPU 가 준 값을 그대로 씁니다.

#include "tone_shared.hlsli"

cbuffer ExposureConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    float Multiplier;
    float3 Padding1;
};

[numthreads(8, 8, 1)]
void ExposureMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];
    Destination[coordinate] = float4(source.rgb * Multiplier, source.a);
}
