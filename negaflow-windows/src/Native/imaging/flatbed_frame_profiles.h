#pragma once

#include "flatbed_frame_grid_types.h"

#include "negaflow/imaging/flatbed_frame_grid_detector.h"

#include <optional>
#include <vector>

namespace negaflow::imaging::flatbed_detail {

// 포맷이 정한 물리 치수를 이 미리보기의 화소 치수로 바꿉니다. 미리보기 해상도가
// 터무니없으면 답하지 않습니다.
[[nodiscard]] std::optional<Geometry> make_geometry(
    const FlatbedFramePreview& preview,
    FlatbedFrameFormat format) noexcept;

// 세로줄마다의 평균과 국소 대비입니다. 필름 스트립이 놓인 열을 찾는 데 씁니다.
[[nodiscard]] ColumnProfiles column_profiles(const FlatbedFramePreview& preview);

// 스트립 양옆 유리면의 평균입니다. 스트립 안 밝기를 이 값 기준으로 봅니다.
[[nodiscard]] std::vector<double> side_means(
    const FlatbedFramePreview& preview,
    IntRange slot,
    const std::vector<double>& fallback);

// 한 스트립 안 가로줄마다의 평균·대비·주변값입니다. 프레임 간격을 여기서 찾습니다.
[[nodiscard]] RowProfiles row_profiles(
    const FlatbedFramePreview& preview,
    IntRange slot);

}  // namespace negaflow::imaging::flatbed_detail
