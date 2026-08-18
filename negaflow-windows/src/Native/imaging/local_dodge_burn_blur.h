#pragma once

#include "local_dodge_burn_types.h"

#include <cstdint>
#include <vector>

namespace negaflow::imaging::local_dodge_burn_detail {

[[nodiscard]] std::vector<float> box_blur(
    const std::vector<float>& source,
    std::uint32_t width,
    std::uint32_t height,
    int radius);

// 시그마가 작을 때 쓰는 분리 가능한 가우시안입니다.
[[nodiscard]] std::vector<float> direct_gaussian_blur(
    const std::vector<float>& source,
    std::uint32_t width,
    std::uint32_t height,
    float sigma);

// 시그마가 커지면 직접 가우시안 대신 박스 세 번으로 근사합니다 - 커널 폭이 이미지만큼
// 커지면 직접 방식이 이미지 크기에 제곱으로 느려집니다.
[[nodiscard]] std::vector<float> scalable_gaussian_blur(
    const std::vector<float>& source,
    std::uint32_t width,
    std::uint32_t height,
    float sigma);

// 마스크 가장자리를 이 시그마로 무르게 합니다. 시그마가 문턱보다 작으면 그대로 둡니다.
void soften_mask(
    MaskResult& mask,
    const WorkingImage& image,
    float sigma);

}  // namespace negaflow::imaging::local_dodge_burn_detail
