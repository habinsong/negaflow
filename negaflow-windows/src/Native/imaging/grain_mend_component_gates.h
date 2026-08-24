#pragma once

#include "grain_mend_component_types.h"
#include "grain_mend_detector.h"

#include "grain_mend_shape.h"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

// 컴포넌트의 형태 측정. grain_mend_shape 한 곳만 씁니다 — 게이트·기각·분류가 같은 모양을
// 봐야 합니다.
[[nodiscard]] PcaMetrics pca_metrics(
    const Component& component,
    std::uint32_t image_width) noexcept;

// 후보 화소를 8이웃 연결요소로 묶습니다. `evidence` 는 비트 마스크로, 1 이 먼지
// 2 가 스크래치입니다. `strong` 은 히스테리시스 코어를 세는 데만 씁니다.
[[nodiscard]] std::vector<Component> collect_components(
    const DetectionImage& image,
    const std::vector<std::uint8_t>& weak,
    const std::vector<std::uint8_t>& strong,
    std::uint8_t evidence);

[[nodiscard]] double bounding_aspect(const Component& component) noexcept;

[[nodiscard]] double labeled_maximum_thickness(
    double dust_sensitivity) noexcept;

// 먼지 게이트: 면적·경계상자 aspect 로 보고, 넘치면 평균 두께로 한 번 더 봅니다.
[[nodiscard]] bool passes_dust_gate(
    const Component& component,
    std::size_t maximum_area,
    double maximum_aspect,
    double minimum_thickness,
    double maximum_thickness) noexcept;

// 스크래치 게이트: 경계상자와 PCA 중 하나만 통과해도 됩니다. 두꺼운 것은 먼저 뺍니다.
[[nodiscard]] bool passes_scratch_gate(
    const Component& component,
    std::uint32_t image_width,
    std::uint32_t minimum_length,
    double minimum_aspect) noexcept;

}  // namespace negaflow::imaging::grain_mend_detail
