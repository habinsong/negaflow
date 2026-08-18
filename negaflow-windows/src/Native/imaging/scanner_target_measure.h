#pragma once

#include "negaflow/core/pixel.h"

namespace negaflow::imaging::scanner_target_detail {

// 안쪽 사각형에서 잰 밝기 분포입니다.
struct InsetStats final { double median; double p05; double p95; };

// 가장자리를 `fraction` 만큼 뺀 안쪽만 재어 홀더 그림자와 검은 띠를 셈에서 뺍니다.
// 표본이 모자라면 false 를 냅니다.
[[nodiscard]] bool measure_inset(
    negaflow::core::ImageView image,
    double fraction,
    InsetStats& stats);

// 이 장면에 룩을 얼마나 실을지의 가중치입니다. 대비가 이미 큰 장면은 덜 싣습니다 -
// 룩은 스캐너의 톤 곡선을 흉내 내는 것이지 대비를 더하는 것이 아닙니다.
// `median` 에는 고른 안쪽 사각형의 중앙값을 씁니다.
[[nodiscard]] double scene_anchor_weight(
    negaflow::core::ImageView image,
    double& median);

}  // namespace negaflow::imaging::scanner_target_detail
