// 필름 스톡 색 큐브(33³ 3D LUT)입니다.
//
// macOS  : `FilmEmulationStage` 의 `CIColorCube`
// CPU 판 : `imaging/film_emulation_color.cpp` `apply_film_emulation_color_cube` / `sample_cube`
//
// ☠️ **하드웨어 삼선형(`Texture3D` + `SampleLevel`)을 쓰지 않습니다.** D3D11 은 필터
//    가중치의 서브텍셀 정밀도를 **8비트만** 보장합니다. 33³ 큐브의 이웃 간격이 값으로
//    1/32 쯤이라 그 양자화가 출력에 6e-05 대로 실려 `1e-5` 동치를 못 지킵니다.
//    표를 구조화 버퍼로 받고 보간을 **CPU 와 같은 순서의 float 연산으로** 직접 합니다.
//
// 도메인: 입력은 확장 선형 sRGB, 큐브는 sRGB 코드 좌표 [0,1] 입니다. 인코딩 → 클램프 →
// 삼선형 → 디코딩. **클램프를 빼지 마십시오** — 측정되지 않은 영역을 외삽하게 됩니다.

#include "tone_shared.hlsli"

// `imaging::film_emulation_cube_dimension`.
#define NEGAFLOW_CUBE_DIMENSION 33

// `FilmEmulationCubeEntry` 는 float 셋(12바이트)입니다. 원소 크기가 어긋나면 컴파일도
// 실행도 통과하고 **값만 틀립니다.**
StructuredBuffer<float3> Cube : register(t1);

cbuffer FilmEmulationCubeConstants : register(b0) {
    uint2 Extent;
    float2 Padding0;
};

// `film_emulation_color.cpp` `cube_index` 와 같은 배치입니다 — 빨강이 가장 빠르게 돕니다.
uint CubeIndex(uint red, uint green, uint blue) {
    return ((blue * NEGAFLOW_CUBE_DIMENSION) + green) * NEGAFLOW_CUBE_DIMENSION + red;
}

// `interpolate` 와 같은 식입니다: `lower + ((upper - lower) * fraction)`.
// 괄호를 바꾸면 마지막 비트가 달라집니다.
float3 Interpolate(float3 lower, float3 upper, float fraction) {
    return lower + ((upper - lower) * fraction);
}

// `sample_cube` 를 그대로 옮긴 것입니다. 잘림(`uint(x)`)·`min` 상한·보간 순서
// (빨강 → 초록 → 파랑)까지 같습니다.
float3 SampleCube(float red, float green, float blue) {
    float maximumCoordinate = float(NEGAFLOW_CUBE_DIMENSION - 1);
    float redCoordinate = red * maximumCoordinate;
    float greenCoordinate = green * maximumCoordinate;
    float blueCoordinate = blue * maximumCoordinate;

    uint redLow = uint(redCoordinate);
    uint greenLow = uint(greenCoordinate);
    uint blueLow = uint(blueCoordinate);
    uint redHigh = min(redLow + 1u, uint(NEGAFLOW_CUBE_DIMENSION - 1));
    uint greenHigh = min(greenLow + 1u, uint(NEGAFLOW_CUBE_DIMENSION - 1));
    uint blueHigh = min(blueLow + 1u, uint(NEGAFLOW_CUBE_DIMENSION - 1));
    float redFraction = redCoordinate - float(redLow);
    float greenFraction = greenCoordinate - float(greenLow);
    float blueFraction = blueCoordinate - float(blueLow);

    float3 c000 = Cube[CubeIndex(redLow, greenLow, blueLow)];
    float3 c100 = Cube[CubeIndex(redHigh, greenLow, blueLow)];
    float3 c010 = Cube[CubeIndex(redLow, greenHigh, blueLow)];
    float3 c110 = Cube[CubeIndex(redHigh, greenHigh, blueLow)];
    float3 c001 = Cube[CubeIndex(redLow, greenLow, blueHigh)];
    float3 c101 = Cube[CubeIndex(redHigh, greenLow, blueHigh)];
    float3 c011 = Cube[CubeIndex(redLow, greenHigh, blueHigh)];
    float3 c111 = Cube[CubeIndex(redHigh, greenHigh, blueHigh)];

    float3 c00 = Interpolate(c000, c100, redFraction);
    float3 c10 = Interpolate(c010, c110, redFraction);
    float3 c01 = Interpolate(c001, c101, redFraction);
    float3 c11 = Interpolate(c011, c111, redFraction);
    float3 c0 = Interpolate(c00, c10, greenFraction);
    float3 c1 = Interpolate(c01, c11, greenFraction);
    return Interpolate(c0, c1, blueFraction);
}

[numthreads(8, 8, 1)]
void FilmEmulationCubeMain(uint3 id : SV_DispatchThreadID) {
    if (id.x >= Extent.x || id.y >= Extent.y) {
        return;
    }
    uint2 coordinate = id.xy;
    float4 source = Source[coordinate];
    float3 encoded = float3(
        clamp(LinearToSrgbEncoded(source.r), 0.0, 1.0),
        clamp(LinearToSrgbEncoded(source.g), 0.0, 1.0),
        clamp(LinearToSrgbEncoded(source.b), 0.0, 1.0));
    float3 sampled = SampleCube(encoded.r, encoded.g, encoded.b);
    Destination[coordinate] = float4(
        SrgbEncodedToLinear(sampled.r),
        SrgbEncodedToLinear(sampled.g),
        SrgbEncodedToLinear(sampled.b),
        source.a);
}
