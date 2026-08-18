#pragma once

#include "flatbed_frame_grid_types.h"

#include "negaflow/imaging/flatbed_frame_grid_detector.h"

#include <optional>
#include <vector>

namespace negaflow::imaging::flatbed_detail {

[[nodiscard]] double pixel_at(
    const FlatbedFramePreview& preview,
    int x,
    int y) noexcept;

// 정렬한 표본의 분위값입니다. 값을 복사로 받아 호출부의 순서를 지킵니다.
[[nodiscard]] double quantile(std::vector<double> values, double fraction);

[[nodiscard]] double median(std::vector<double> values);

// 중앙값과 로버스트 산포로 0…1 에 맞춘 신호입니다. 스캐너마다 다른 노출 차이를 지웁니다.
[[nodiscard]] std::vector<double> robust_normalized(const std::vector<double>& values);

[[nodiscard]] std::vector<double> moving_average(
    const std::vector<double>& values,
    int radius);

// 신호를 둘로 가르는 문턱입니다. 두 무리로 갈리지 않으면 답하지 않습니다.
[[nodiscard]] std::optional<double> split_threshold(const std::vector<double>& values);

// 문턱을 넘는 구간들입니다.
[[nodiscard]] std::vector<IntRange> included_runs(
    const std::vector<double>& values,
    double threshold);

// 간격이 좁은 구간끼리 잇습니다. 한 칸짜리 끊김으로 필름 띠가 둘로 갈리지 않게 합니다.
[[nodiscard]] std::vector<IntRange> bridge_ranges(
    const std::vector<IntRange>& ranges,
    int maximum_gap);

}  // namespace negaflow::imaging::flatbed_detail
