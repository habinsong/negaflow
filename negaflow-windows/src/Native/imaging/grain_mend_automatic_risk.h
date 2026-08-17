#pragma once

#include "grain_mend_component_classification.h"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

// macOS `SoftwareDefectRemoval.wholeFrameAutomaticCandidateFractionLimit` — 전체 프레임
// 자동에서 "오검출 위험 높음" 경고를 띄우는 검출 원화소 비율입니다. FILM-R v2 44쌍에서 이
// 값을 넘긴 프레임 상당수가 실제로 큰 오검출이었습니다.
inline constexpr double whole_frame_automatic_candidate_fraction_limit = 0.0006;
// 같은 경고의 지역 밀도 기준입니다.
inline constexpr double whole_frame_automatic_local_density_limit = 0.02;
// 국소 밀도를 재는 최소 프레임 짧은 변과 타일 한 변 규칙입니다.
inline constexpr std::uint32_t whole_frame_automatic_minimum_short_side = 1'024U;
inline constexpr std::uint32_t whole_frame_automatic_minimum_tile_side = 64U;
inline constexpr std::uint32_t whole_frame_automatic_tile_divisor = 24U;
// 아주 작은 프레임에서 비율 기준이 과민해지지 않게 막는 화소 하한입니다.
inline constexpr double whole_frame_automatic_minimum_candidate_pixels = 512.0;

struct AutomaticRisk final {
    bool false_positive_risk{false};
    double candidate_pixel_fraction{0.0};
};

// macOS `applyingWholeFrameAutomaticRiskFlag` — 자동 결과에 위험 플래그만 붙입니다.
// **성분은 하나도 버리지 않습니다.** 정상 구조가 대량 검출된 경우와 실제로 먼지가 많은
// 장면을 단일 RGB 이미지로 구분할 수 없어서, 예전에는 자동을 통째로 중지했지만 그러면
// 정작 먼지·스크래치가 많은 프레임에서 자동을 전혀 쓸 수 없었습니다. 결과는 그대로
// 돌려주고 화면이 경고만 표시합니다 — 제외는 사용자가 합니다.
[[nodiscard]] AutomaticRisk measure_automatic_risk(
    const std::vector<ClassifiedComponent>& components,
    std::uint32_t width,
    std::uint32_t height);

}  // namespace negaflow::imaging::grain_mend_detail
