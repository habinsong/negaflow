#pragma once

#include "negaflow/core/cancel_flag.h"
#include "negaflow/imaging/grain_mend_classifier.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

// macOS `SoftwareDefectRemoval.detectComponents` 의 요청입니다. 자동과 가이드가 같은 함수를
// 쓰고 `constrained_region` 하나로 갈립니다 — macOS 도 그렇습니다.
struct AutomaticDetection {
    // 원본 화소 기준 검출 범위입니다. 자동은 프레임 전체입니다.
    std::uint32_t origin_x = 0U;
    std::uint32_t origin_y = 0U;
    std::uint32_t width = 0U;
    std::uint32_t height = 0U;
    double dust_sensitivity = 0.0;
    double scratch_sensitivity = 0.0;
    double protect_detail = 0.0;
    // 사용자가 ROI 로 범위를 지목했는지. macOS `constrainedRegion` 과 같습니다 — 참이면 먼지
    // 면적 상한이 커지고(×48) 구조선 격자 배제를 끕니다.
    bool constrained_region = false;
};

// Full-resolution automatic detection uses non-overlapping cores with a
// detector halo. Candidate kinds stay separate until frame-wide stitching so
// structure-line rejection never drops dust that touches a scratch.
[[nodiscard]] std::vector<std::uint8_t> build_tiled_automatic_mask(
    const WorkingImage& image,
    const AutomaticDetection& request,
    std::size_t& accepted_pixels,
    std::vector<ClassifiedComponent>* components = nullptr,
    negaflow::core::CancelFlag cancel = {});

}  // namespace negaflow::imaging::grain_mend_detail
