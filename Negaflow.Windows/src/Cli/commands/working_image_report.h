#pragma once

#include "negaflow/imaging/scanner_to_working.h"

#include <array>
#include <cstdint>

namespace negaflow::cli {

struct WorkingImageStatistics final {
    std::array<float, 4> minimum{};
    std::array<float, 4> maximum{};
    std::uint64_t fingerprint_fnv1a64{0};
};

[[nodiscard]] WorkingImageStatistics compute_working_image_statistics(
    const negaflow::imaging::WorkingImage& image) noexcept;

}  // namespace negaflow::cli
