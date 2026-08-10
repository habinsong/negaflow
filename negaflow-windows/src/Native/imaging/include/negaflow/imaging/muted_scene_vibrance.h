#pragma once

#include "negaflow/core/pixel.h"

namespace negaflow::imaging {

struct MutedSceneVibranceInfo final {
    double mean_saturation{0.5};
    double amount{0.0};
    bool applied{false};
};

struct MutedSceneVibranceResult final {
    negaflow::core::KernelStatus status{
        negaflow::core::KernelStatus::invalid_argument};
    MutedSceneVibranceInfo info{};
};

// Measures HSV saturation from a small linear proxy and applies a bounded
// low-chroma-first boost in place. Monochrome inputs are an explicit identity.
[[nodiscard]] MutedSceneVibranceResult apply_muted_scene_vibrance(
    negaflow::core::ImageView image,
    bool monochrome) noexcept;

}  // namespace negaflow::imaging
