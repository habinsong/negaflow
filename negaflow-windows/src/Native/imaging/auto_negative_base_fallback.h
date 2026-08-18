#pragma once

#include "film_base_sampling.h"

#include "negaflow/imaging/auto_negative_base_resolver.h"

#include <optional>
#include <vector>

namespace negaflow::imaging::auto_base_detail {

// 프레임 사이 띠에서 잽니다. 여백이 화면 밖으로 잘린 스캔에서 마지막으로 남는 실제
// 베이스입니다.
[[nodiscard]] std::optional<film_base_detail::BaseMeasurement> strip_fallback_base(
    const film_base_detail::SampleGrid& grid,
    NegativeFilmType film_type,
    const std::vector<bool>* excluded);

// 베이스가 한 조각도 안 보일 때, 장면 가장자리의 가장 밝은 쪽에서 추정합니다. 이것은
// 측정이 아니라 추정이며, 호출부는 결과의 provenance 를 그렇게 적어야 합니다.
[[nodiscard]] std::optional<film_base_detail::BaseMeasurement> scene_edge_fallback_base(
    const WorkingImage& image,
    NegativeFilmType film_type);

}  // namespace negaflow::imaging::auto_base_detail
