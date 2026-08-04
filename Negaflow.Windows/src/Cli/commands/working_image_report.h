#pragma once

#include "negaflow/imaging/scanner_to_working.h"

#include <array>
#include <cstdint>
#include <string_view>

namespace negaflow::cli {

inline constexpr std::string_view working_pixel_fingerprint_algorithm_version =
    "fnv1a64-rgba32f-bits-le-v1";

struct WorkingImageStatistics final {
    bool valid{false};
    std::array<float, 4> minimum{};
    std::array<float, 4> maximum{};
    std::uint64_t fingerprint_fnv1a64{0};
};

[[nodiscard]] WorkingImageStatistics compute_working_image_statistics(
    const negaflow::imaging::WorkingImage& image) noexcept;

}  // namespace negaflow::cli
