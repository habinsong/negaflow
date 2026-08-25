#pragma once

#include <cstdint>
#include <span>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

[[nodiscard]] std::vector<float> opening(
    const std::vector<float>& source,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t radius);

[[nodiscard]] std::vector<float> closing(
    const std::vector<float>& source,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t radius);

[[nodiscard]] std::vector<float> bipolar_top_hat(
    const std::vector<float>& source,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t radius);

// 같은 반경으로 채널 셋의 양극 톱햇을 한 왕복으로 돌립니다.
// 실패하면 빈 배열 셋을 돌려주고 호출부가 평면마다 CPU 로 갑니다.
struct RgbPlanes final {
    std::vector<float> red{};
    std::vector<float> green{};
    std::vector<float> blue{};
};

[[nodiscard]] RgbPlanes opening_rgb(
    std::span<const float> red,
    std::span<const float> green,
    std::span<const float> blue,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t radius);

[[nodiscard]] RgbPlanes closing_rgb(
    std::span<const float> red,
    std::span<const float> green,
    std::span<const float> blue,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t radius);

[[nodiscard]] RgbPlanes close_open_rgb(
    std::span<const float> red,
    std::span<const float> green,
    std::span<const float> blue,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t radius);

[[nodiscard]] RgbPlanes bipolar_top_hat_rgb(
    std::span<const float> red,
    std::span<const float> green,
    std::span<const float> blue,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t radius);

[[nodiscard]] std::vector<float> box_mean(
    std::span<const float> source,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t radius);

}  // namespace negaflow::imaging::grain_mend_detail
