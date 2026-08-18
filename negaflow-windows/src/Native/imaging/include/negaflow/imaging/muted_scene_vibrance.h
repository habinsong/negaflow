#pragma once

#include "negaflow/core/pixel.h"

#include <cstdint>

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

// 실측 `CIVibrance` 표에서 amount 판 두 장을 고르는 것. 화소마다 같은 값이라
// 화소 루프 밖에서 한 번만 정해집니다.
//
// ☠️ **GPU 판이 이것을 그대로 씁니다.** 두 곳에서 고르면 판이 어긋나는 순간 색이
//    통째로 달라집니다 — 그때는 오차가 1e-5 가 아니라 0.0x 로 나옵니다.
struct VibrancePlaneSelection final {
    std::uint32_t low{0U};
    float blend{0.0F};
};

[[nodiscard]] VibrancePlaneSelection select_vibrance_planes(float amount) noexcept;

// Measures HSV saturation from a small linear proxy and applies a bounded
// low-chroma-first boost in place. Monochrome inputs are an explicit identity.
[[nodiscard]] MutedSceneVibranceResult apply_muted_scene_vibrance(
    negaflow::core::ImageView image,
    bool monochrome) noexcept;

}  // namespace negaflow::imaging
