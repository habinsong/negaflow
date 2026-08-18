#pragma once

#include "film_base_sampling.h"

#include "negaflow/imaging/auto_negative_base_resolver.h"

#include <cstddef>
#include <optional>
#include <vector>

namespace negaflow::imaging::auto_base_detail {

// 고른 칸들이 한 덩어리로 뭉쳐 있을 때만 그 측정을 냅니다.
[[nodiscard]] std::optional<FilmBaseMeasurement> measure_selected(
    FilmBaseMeasurementMethod method,
    const film_base_detail::SampleGrid& grid,
    const std::vector<std::size_t>& selected,
    std::size_t candidate_count);

// 가장자리를 따라 끊기지 않고 이어진 밝은 띠에서 베이스를 잽니다 - 스캔에 미노광
// 여백이 통째로 들어온, 가장 믿을 수 있는 경우입니다.
[[nodiscard]] std::optional<FilmBaseMeasurement> continuous_border_base(
    const film_base_detail::SampleGrid& grid,
    NegativeFilmType film_type,
    const std::vector<bool>* excluded);

// 여백이 이어져 있지 않을 때, 화면 곳곳에 흩어진 밝은 칸에서 잽니다. 후보가 전체의
// 2% 에 못 미치면 답하지 않습니다.
[[nodiscard]] std::optional<FilmBaseMeasurement> distributed_base(
    const film_base_detail::SampleGrid& grid,
    NegativeFilmType film_type,
    const std::vector<bool>* excluded);

}  // namespace negaflow::imaging::auto_base_detail
