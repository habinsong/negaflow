#pragma once

#include "negaflow/imaging/grain_mend_classifier.h"

#include <cstdint>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

// macOS `SoftwareDefectRemoval.stitchRegionDefectTiles`.
// 타일마다 이미 분류된 성분의 **core 화소**를 전역 좌표로 받은 뒤, 종류별로
// 겹침·8-연결 union 하고, 분류는 **가장 높은 confidence 조각을 유지**한다.
// 합친 덩어리를 다시 PCA 하지 않는다 — 다시 분류하면 타일 경계에서 세로가 가로로 바뀐다.
[[nodiscard]] std::vector<ClassifiedComponent> stitch_region_defect_tiles(
    const std::vector<ClassifiedComponent>& mapped,
    std::uint32_t width,
    std::uint32_t height);

}  // namespace negaflow::imaging::grain_mend_detail
