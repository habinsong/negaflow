#pragma once

#include "flatbed_frame_grid_types.h"

#include "negaflow/core/cancel_flag.h"

#include <cstdint>
#include <optional>
#include <utility>
#include <vector>

namespace negaflow::imaging::flatbed_detail {

// 표본에 직선을 맞춥니다. 두 점 미만이면 답하지 않습니다.
[[nodiscard]] std::optional<std::pair<double, double>> fit_line(
    const std::vector<std::pair<double, double>>& samples) noexcept;

// 이상점을 걸러 가며 직선을 맞춥니다. 프레임 하나를 잘못 잡아도 격자가 끌려가지 않습니다.
[[nodiscard]] std::optional<std::pair<double, double>> robust_line(
    const std::vector<std::pair<double, double>>& samples);

// 예측한 간격 자리를 증거의 실제 골짜기로 당깁니다.
[[nodiscard]] double refined_center(
    double center,
    const GapEvidence& evidence,
    double radius,
    double half) noexcept;

// 간격 증거에 등간격 격자를 맞춥니다. 확신이 바닥 아래면 답하지 않습니다.
[[nodiscard]] std::optional<Grid> fit_grid(
    const GapEvidence& evidence,
    const Geometry& geometry,
    negaflow::core::CancelFlag cancel);

// 격자 경계 사이를 프레임 구간으로 바꿉니다.
[[nodiscard]] std::vector<DoubleRange> frame_spans(
    const Grid& grid,
    IntRange band,
    const Geometry& geometry);

// 실제로 필름이 든 구간만 남깁니다. 홀더 끝의 빈 칸을 프레임으로 내지 않습니다.
[[nodiscard]] std::vector<DoubleRange> occupied(
    const std::vector<DoubleRange>& spans,
    const RowProfiles& rows,
    double noise,
    std::uint32_t height);

}  // namespace negaflow::imaging::flatbed_detail
