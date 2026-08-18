#pragma once

#include "film_scan_denoise_types.h"

#include <array>
#include <cstdint>
#include <vector>

namespace negaflow::imaging::film_scan_denoise_detail {

// 분리 가능한 가우시안입니다. 반지름은 조율값 한 표의 gaussian_radius 입니다.
[[nodiscard]] std::vector<Rgb> gaussian_blur(
    const std::vector<Rgb>& source,
    std::uint32_t width,
    std::uint32_t height);

[[nodiscard]] float median9(std::array<float, 9U> values) noexcept;

// 3x3 중앙값입니다. 한 화소짜리 튐(임펄스)만 지우고 경계는 남깁니다.
[[nodiscard]] std::vector<Rgb> median3(
    const std::vector<Rgb>& source,
    std::uint32_t width,
    std::uint32_t height);

[[nodiscard]] std::vector<float> box_blur(
    const std::vector<float>& source,
    std::uint32_t width,
    std::uint32_t height,
    int radius);

[[nodiscard]] std::vector<Rgb> box_blur(
    const std::vector<Rgb>& source,
    std::uint32_t width,
    std::uint32_t height,
    int radius);

// 휘도를 안내로 삼는 유도 필터입니다. 색 잡음을 뭉개면서 경계는 휘도가 붙잡습니다.
[[nodiscard]] std::vector<Rgb> guided_base(
    const std::vector<Rgb>& source,
    const std::vector<float>& guide,
    std::uint32_t width,
    std::uint32_t height,
    int radius);

}  // namespace negaflow::imaging::film_scan_denoise_detail
