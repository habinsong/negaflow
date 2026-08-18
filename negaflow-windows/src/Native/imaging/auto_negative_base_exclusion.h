#pragma once

#include "film_base_sampling.h"

#include "negaflow/imaging/auto_negative_base_resolver.h"

#include <optional>
#include <vector>

namespace negaflow::imaging::auto_base_detail {

// 고른 격자 칸 둘레를 한 칸씩 넓힙니다. 베이스와 화면 경계에 걸친 칸을 함께 빼려는
// 것입니다.
[[nodiscard]] std::vector<bool> dilate(
    const std::vector<bool>& selected,
    const film_base_detail::SampleGrid& grid);

// 밝은 쪽에서 실제로 뭉쳐 있는 밝기 봉우리입니다. 스캔 밖 흰 여백처럼 베이스보다 밝지만
// 필름이 아닌 자리를 가려내는 기준이 됩니다. 봉우리가 하나뿐이면 답하지 않습니다.
[[nodiscard]] std::optional<double> brightest_coherent_mode(
    const film_base_detail::SampleGrid& grid,
    NegativeFilmType film_type);

// 필름이 아닌 자리(빈 베드·홀더 창)를 표시한 제외 마스크입니다. 가릴 근거가 없으면
// 답하지 않고, 그때 호출부는 제외 없이 후보를 찾습니다.
[[nodiscard]] std::optional<std::vector<bool>> non_film_exclusion(
    const film_base_detail::SampleGrid& grid,
    NegativeFilmType film_type);

}  // namespace negaflow::imaging::auto_base_detail
