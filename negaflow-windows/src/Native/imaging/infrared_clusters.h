#pragma once

#include "infrared_detection_types.h"

#include "negaflow/imaging/infrared_defect_detector.h"

#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace negaflow::imaging::infrared_detail {

// 성분 하나를 UI 가 읽는 요약으로 바꿉니다. 2차 모멘트로 길쭉함과 각도를 재어 먼지와
// 가로·세로·대각 스크래치를 가릅니다. 미리보기 점은 240개로 성글게 뽑습니다.
[[nodiscard]] InfraredDetectedComponent summarize_component(
    const RawComponent& component,
    std::span<const std::size_t> correction_pixels,
    std::span<const float> attenuation,
    std::uint32_t width);

// 감쇠 평면을 타일로 잘라 보정이 필요한 자리만 묶음으로 냅니다. 각 묶음은 자기 ROI 의
// 감쇠 16비트 값과 코어 마스크를 소유하므로 호출부가 원본 평면을 들고 있을 필요가 없습니다.
[[nodiscard]] std::vector<InfraredCorrectionCluster> render_clusters(
    std::span<const float> attenuation,
    const std::vector<std::size_t>& core_pixels,
    float threshold,
    std::uint32_t width,
    std::uint32_t height,
    const InfraredDetectorParameters& parameters);

}  // namespace negaflow::imaging::infrared_detail
