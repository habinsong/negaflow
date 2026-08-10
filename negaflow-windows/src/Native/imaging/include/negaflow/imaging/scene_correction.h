#pragma once

#include "negaflow/core/pixel.h"

#include <cstdint>

namespace negaflow::imaging {

struct SceneCorrectionParameters final {
    bool auto_levels{false};
    bool auto_neutral_balance{false};
    bool negative_source{true};
};

struct SceneCorrectionInfo final {
    bool auto_levels_applied{false};
    bool neutral_balance_applied{false};
    std::uint64_t sampled_pixels{0U};
};

// Applies the two opt-in scene-adaptive corrections at the same pipeline boundary as
// macOS Chromabase: after negative inversion (or positive decode) and before ColorModel.
// The image is modified in place; disabled or ineligible corrections are exact no-ops.
[[nodiscard]] negaflow::core::KernelStatus apply_scene_correction(
    negaflow::core::ImageView image,
    const SceneCorrectionParameters& parameters,
    SceneCorrectionInfo& info) noexcept;

}  // namespace negaflow::imaging
