#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/analysis_region.h"

#include <cstdint>
#include <optional>

namespace negaflow::imaging {

struct MutedSceneVibranceInfo final {
    double mean_saturation{0.5};
    double amount{0.0};
    bool applied{false};
    // 평균 채도를 이번 호출이 쟀거나 받아 썼는가(흑백이거나 검증에서 일찍 끝나면 false).
    bool saturation_measured{false};
};

struct MutedSceneVibranceResult final {
    negaflow::core::KernelStatus status{
        negaflow::core::KernelStatus::invalid_argument};
    MutedSceneVibranceInfo info{};
};

// 크로스플랫폼 Vibrance 3D 룩업 테이블에서 amount 판 두 장을 고르는 것. 화소마다 같은 값이라
// 화소 루프 밖에서 한 번만 정해집니다.
//
// **GPU 판이 이것을 그대로 씁니다.** 두 곳에서 고르면 판이 어긋나는 순간 색이
// 통째로 달라집니다 — 그때는 오차가 1e-5 가 아니라 0.0x 로 나옵니다.
struct VibrancePlaneSelection final {
    std::uint32_t low{0U};
    float blend{0.0F};
};

[[nodiscard]] VibrancePlaneSelection select_vibrance_planes(float amount) noexcept;

// Measures HSV saturation from a small linear proxy and applies a bounded
// low-chroma-first boost in place. Monochrome inputs are an explicit identity.
// `region` 이 있으면 장면 채도를 크롭한 사진 영역 안에서만 잽니다(적용은 전체).
// `reused_mean_saturation` 은 같은 화상·같은 영역에서 이미 잰 평균 채도입니다. 있으면 축소·측정을
// 건너뛰고 그 값으로 세기를 정합니다(측정이 결정적이므로 결과 화소는 같습니다).
[[nodiscard]] MutedSceneVibranceResult apply_muted_scene_vibrance(
    negaflow::core::ImageView image,
    bool monochrome,
    const std::optional<AnalysisRegion>& region = std::nullopt,
    const std::optional<double>& reused_mean_saturation = std::nullopt) noexcept;

} // namespace negaflow::imaging
