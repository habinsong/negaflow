#pragma once

#include "texture_stage_math.h"

#include <cstddef>

namespace negaflow::imaging::texture_stage_detail {

// 텍스처 단계가 거는 다섯 가지 효과입니다. 거는 순서는 texture_stage.cpp 가 소유합니다.

// 언샤프 마스크입니다. `radius` 는 화소, `intensity` 는 0…1 입니다.
void apply_unsharp(
    WorkingImage& image,
    float radius,
    float intensity,
    std::size_t& scratch_peak_bytes);

// 좌표 해시 기반 그레인입니다. 잡음이 진행 순서가 아니라 절대 좌표의 함수이므로 행을
// 나눠 병렬로 돌려도 같은 그림이 나옵니다.
void apply_grain(WorkingImage& image, float strength) noexcept;

// 네거티브 명료도입니다. 부호 있는 값이라 음수면 무르게 합니다.
void apply_negative_clarity(
    WorkingImage& image,
    float clarity,
    std::size_t& scratch_peak_bytes);

// 밝은 자리에서 번지는 붉은 헐레이션입니다.
void apply_halation(
    WorkingImage& image,
    float strength,
    std::size_t& scratch_peak_bytes);

// 비네트입니다. 부호 있는 값이라 음수면 가장자리를 밝힙니다.
void apply_vignette(WorkingImage& image, float vignette) noexcept;

}  // namespace negaflow::imaging::texture_stage_detail
