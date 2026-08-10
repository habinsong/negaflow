#pragma once

#include "negaflow/core/pixel.h"

#include <cstddef>

namespace negaflow::imaging {

struct RescueGradeInfo final {
    bool applied{false};
    std::size_t eligible_band_count{0U};
    std::size_t covered_tile_count{0U};
    std::size_t training_sample_count{0U};
    std::size_t holdout_sample_count{0U};
};

// EXPIRED is a recovery target, not a creative look. It changes pixels only when
// multiple luminance bands contain spatially distributed, low-scatter neutral-axis
// drift that independently agrees in a deterministic holdout set.
[[nodiscard]] negaflow::core::KernelStatus apply_rescue_grade(
    negaflow::core::ImageView image,
    bool color_film,
    RescueGradeInfo& info) noexcept;

}  // namespace negaflow::imaging
