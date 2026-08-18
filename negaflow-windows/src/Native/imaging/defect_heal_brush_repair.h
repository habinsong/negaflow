#pragma once

#include "defect_heal_brush_types.h"

#include <cstddef>
#include <vector>

namespace negaflow::imaging::heal_brush_detail {

// 조각 하나를 실제로 고쳐 아직 앉히지 않은 패치로 냅니다. `preceding` 은 앞선 조각들의
// 패치로, 겹친 획이 앞 결과 위에서 이어지게 합니다. ROI 가 너무 작으면 빈 패치를 냅니다.
// 성분 치유가 한 곳이라도 실패하면 `used_fallback` 을 세우고 성분 복구 경로로 넘어갑니다.
[[nodiscard]] StoredPatch make_patch(
    const WorkingImage& base,
    const std::vector<StoredPatch>& preceding,
    const BrushChunk& chunk,
    bool& used_fallback,
    std::size_t& component_count,
    std::size_t& healed_pixels);

}  // namespace negaflow::imaging::heal_brush_detail
