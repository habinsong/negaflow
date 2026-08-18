#pragma once

#include "grain_mend_detector.h"

#include "negaflow/imaging/kernel_accelerator.h"

#include <vector>

namespace negaflow::imaging::grain_mend_detail {

// 한 각도에서 나온 능선과 그 방향으로 적분한 응답입니다.
struct ScratchAngleMaps final {
    std::vector<float> ridge{};
    std::vector<float> integrated{};
};

// 한 각도만큼 기울인 가는 능선을 찾고, 그 방향으로 적분해 선다움을 셉니다. 여덟 각도를
// 각각 돌려 가장 센 응답을 고르는 것이 macOS 다방향 스크래치 검출과 같은 구조입니다.
// multi_scale 은 macOS `candidatesLeveled`(자동·라벨) 의 curveHalf=6 적분입니다.
void fill_scratch_angle_taps(
    double degrees,
    bool multi_scale,
    negaflow::imaging::ScratchAngleTaps& taps);

void make_scratch_angle_maps(
    const DetectionImage& image,
    double degrees,
    const std::vector<std::uint8_t>& valid,
    float balance_limit,
    bool multi_scale,
    ScratchAngleMaps& result);

}  // namespace negaflow::imaging::grain_mend_detail
