// macOS `ChromabaseMetalKernels.swift:826` `[[stitchable]] float4 digitalBWFilm(...)`.
// Windows CPU 판은 `imaging/digital_bw_emulsion_response.cpp`
// `apply_digital_bw_emulsion_response` 이고, 이 셰이더는 그것과 화소값이 같아야 합니다.
//
// ⚠️ CPU 판은 화소 계산을 **`double`** 로 합니다. 이 셰이더는 float32 입니다.
//    값이 전부 [0,1] 안의 다항식이라 오차가 작을 것으로 보지만, **그것은 시험이 판정합니다.**
//    허용치를 늘리지 말고, 넘으면 원인을 찾으십시오.
//
// 응답 계수(가중·대비·토·숄더·deepen·흑점·백점·강도)는
// `imaging::prepare_digital_bw_emulsion_response` 가 만든 것을 받습니다. 여기서 다시
// 계산하지 마십시오 — 필름 프로파일 표가 CPU 쪽에 있습니다.

#include "tone_shared.hlsli"

cbuffer DigitalBwFilmConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
    float3 Weights;      // 분광 RGB→그레이 가중
    float Contrast;
    float Toe;
    float Shoulder;
    float Deepen;
    float Black;
    float White;
    float Intensity;
    float2 Padding1;
};

[numthreads(8, 8, 1)]
void DigitalBwFilmMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];

    // 분광 그레이는 **선형광**에서 만듭니다. 음수 채널은 0 으로 막습니다(CPU 와 같음).
    float linearGray = dot(max(source.rgb, 0.0), Weights);
    float boundedLinear = clamp(linearGray, 0.0, 1.0);
    // [0,1] 을 넘는 분량은 특성 곡선을 태우지 않고 그대로 되돌려 줍니다 —
    // 하이라이트 여유를 잃지 않기 위한 CPU 판의 `over` 입니다.
    float over = linearGray - boundedLinear;

    // 특성 곡선은 **sRGB 부호화 도메인**에서 평가합니다.
    float encoded = LinearToSrgbEncoded(boundedLinear);

    // 1) 대비 — smootherstep 과의 편차. 음수면 곡선을 반대로 눕혀 대비를 낮춥니다.
    float smoother = encoded * encoded * encoded * ((encoded * ((encoded * 6.0) - 15.0)) + 10.0);
    float result = clamp(encoded + ((smoother - encoded) * Contrast), 0.0, 1.0);

    // 2) 토 — 긴 토는 암부를 들어 올리고, 곧은 토는 더 떨굽니다.
    float low = 1.0 - result;
    result = clamp(result + (Toe * low * low * low), 0.0, 1.0);

    // 3) 숄더 — 넓은 관용도는 명부를 눕혀 담습니다.
    result = clamp(result + (Shoulder * result * result * result), 0.0, 1.0);

    // 4) 반전은 인화지가 뒤를 받치지 않아 검정이 바닥까지 갑니다. 중간톤은 건드리지 않습니다.
    float density = 1.0 - result;
    result = clamp(result * (1.0 - (Deepen * density * density * density)), 0.0, 1.0);

    // 5) 매체의 흑·백 한계. 인화지는 순흑에 붙지 않고, 반전은 붙습니다.
    result = clamp(Black + (result * (White - Black)), 0.0, 1.0);

    // 강도는 지각 도메인에서 섞습니다. 0 이면 유제 특성이 사라지고 중립 그레이만 남습니다.
    result = encoded + ((result - encoded) * Intensity);

    float outputGray = SrgbEncodedToLinear(result) + over;
    Destination[coordinate] = float4(outputGray, outputGray, outputGray, source.a);
}
