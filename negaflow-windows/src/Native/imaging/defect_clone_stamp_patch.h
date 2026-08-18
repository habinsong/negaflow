#pragma once

#include "defect_clone_stamp_types.h"

#include <vector>

namespace negaflow::imaging::clone_stamp_detail {

// 획 하나를 그 획의 ROI 패치로 굽습니다. `preceding` 은 앞선 획들의 패치로, 겹친 획이
// 앞 결과를 원본으로 삼게 합니다. 찍을 것이 없거나 ROI 가 비면 false 를 냅니다.
[[nodiscard]] bool make_patch(
    const WorkingImage& base,
    const std::vector<StoredPatch>& preceding,
    const DefectCloneStroke& stroke,
    StoredPatch& patch);

}  // namespace negaflow::imaging::clone_stamp_detail
