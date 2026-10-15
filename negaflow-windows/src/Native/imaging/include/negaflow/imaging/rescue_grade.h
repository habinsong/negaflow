#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/analysis_region.h"

#include <cstddef>
#include <optional>

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
// `region` 이 있으면 중립축 증거를 크롭한 사진 영역 안에서만 잽니다(적용은 전체). 호스트
// 화소가 최신이어야 합니다 — 호출부가 상주 화상을 먼저 내립니다.
[[nodiscard]] negaflow::core::KernelStatus apply_rescue_grade(
    negaflow::core::ImageView image,
    bool color_film,
    RescueGradeInfo& info,
    const std::optional<AnalysisRegion>& region = std::nullopt) noexcept;

}  // namespace negaflow::imaging
