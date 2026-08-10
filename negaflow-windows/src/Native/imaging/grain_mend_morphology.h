#pragma once

#include <cstdint>
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

[[nodiscard]] std::vector<float> box_mean(
    const std::vector<float>& source,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t radius);

}  // namespace negaflow::imaging::grain_mend_detail
