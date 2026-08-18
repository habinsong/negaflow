#ifndef NEGAFLOW_VIBRANCE_SHARED_HLSLI
#define NEGAFLOW_VIBRANCE_SHARED_HLSLI

// macOS `CIVibrance` 의 **실측 사상**입니다.
//
// CPU 판 : `imaging/vibrance_math.h` `measured_vibrance_scale`
// 표     : `imaging/muted_scene_vibrance_table.cpp` (생성 파일, 33³ × amount 판 6장)
//
// Apple 의 `CIVibrance` 는 비공개 커널이라 수식이 없습니다. 이 저장소는 맥이 렌더한
// 격자를 재서 표로 옮겼고, 화소마다 **정확히 아핀**이라는 것을 확인했습니다:
//
//   out = A + (in − A) · f,   A = (R+G+B)/3,   f = 1 + amount · g
//
// `g` 만 표에서 읽습니다. 앵커는 **산술 평균**이고 Rec.709 휘도가 아닙니다 —
// 휘도로 풀면 최대 0.38 어긋납니다(CPU 헤더의 측정 기록).
//
// ☠️ **amount 판 두 장의 선택은 호스트가 합니다**(`imaging::select_vibrance_planes`).
//    화소마다 같은 값이고, 두 곳에서 고르면 판이 어긋나는 순간 색이 통째로 달라집니다.
//
// ☠️ **모서리마다 판을 먼저 섞고 그 다음 삼선형입니다.** CPU 가 그 순서입니다.
//    삼선형을 판별로 먼저 하고 뒤에 섞으면 수학적으로는 같지만 반올림이 달라집니다.

// 표. `uint16` 원본을 호스트가 float 로 펴서 올립니다 — 셰이더에서 `uint` 를 언패킹하면
// 그 자리에 비트 연산이 붙고, 표는 프레임마다 바뀌지 않으므로 펴 두는 편이 쌉니다.
StructuredBuffer<float> VibranceTable : register(t1);

#define NEGAFLOW_VIBRANCE_SIDE 33

// `vibrance_math.h` 의 `axis` 와 같습니다.
float VibranceAxis(float value, out uint index) {
    float scaled = clamp(value, 0.0, 1.0) * float(NEGAFLOW_VIBRANCE_SIDE - 1);
    float floored = floor(scaled);
    index = min(uint(floored), uint(NEGAFLOW_VIBRANCE_SIDE - 2));
    return scaled - float(index);
}

// `vibrance_math.h` 의 `sample` 과 같은 배치입니다 — 판이 가장 느리고, 판 안에서는
// R 이 느리고 B 가 가장 빠릅니다.
float VibranceSample(uint plane, uint r, uint g, uint b) {
    const uint side = NEGAFLOW_VIBRANCE_SIDE;
    const uint planeStride = side * side * side;
    return VibranceTable[(plane * planeStride) + (r * side * side) + (g * side) + b];
}

// `measured_vibrance_scale` 을 그대로 옮긴 것입니다.
// `low`·`blend` 는 호스트가 `select_vibrance_planes` 로 고른 것입니다.
float MeasuredVibranceScale(
    float3 color, float amount, uint low, float blend, float quantum) {
    uint r0 = 0u;
    uint g0 = 0u;
    uint b0 = 0u;
    float fr = VibranceAxis(color.r, r0);
    float fg = VibranceAxis(color.g, g0);
    float fb = VibranceAxis(color.b, b0);

    float total = 0.0;
    [unroll]
    for (uint dr = 0u; dr < 2u; ++dr) {
        float wr = dr == 1u ? fr : 1.0 - fr;
        [unroll]
        for (uint dg = 0u; dg < 2u; ++dg) {
            float wg = dg == 1u ? fg : 1.0 - fg;
            [unroll]
            for (uint db = 0u; db < 2u; ++db) {
                float wb = db == 1u ? fb : 1.0 - fb;
                float lowValue = VibranceSample(low, r0 + dr, g0 + dg, b0 + db);
                float highValue = VibranceSample(low + 1u, r0 + dr, g0 + dg, b0 + db);
                float corner = lowValue + ((highValue - lowValue) * blend);
                total += wr * wg * wb * corner;
            }
        }
    }
    return 1.0 + (amount * total * quantum);
}

// `apply_measured_vibrance_to_channels` 와 같습니다.
float3 ApplyMeasuredVibrance(
    float3 color, float amount, uint low, float blend, float quantum) {
    float scale = MeasuredVibranceScale(color, amount, low, blend, quantum);
    float anchor = (color.r + color.g + color.b) / 3.0;
    return anchor + ((color - anchor) * scale);
}

#endif  // NEGAFLOW_VIBRANCE_SHARED_HLSLI
