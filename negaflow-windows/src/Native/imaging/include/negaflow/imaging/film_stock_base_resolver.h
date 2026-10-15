#pragma once

#include "negaflow/imaging/manual_negative_developer.h"

#include <array>
#include <optional>
#include <string_view>

namespace negaflow::imaging {

// Immutable bundled stock data used only by the Film base mode. The values are
// the macOS baseline's documented curve readings; this resolver does not claim a
// scanner calibration or replace a measured film base.
struct FilmStockBasePreset final {
    std::array<float, 3> dmin{};
    std::array<float, 3> dmax_normalized{};
    // 이 필름의 채널별 밀도 범위가 번들 컬러 네거티브의 전형(채널별 중앙값)보다 얼마나 넓고
    // 좁은가(기하평균 1) — macOS `FilmStockDmin.relativeRangeFactor`. 데이터시트는 Status M 농도라
    // 스캐너 채널의 절대 비율과 다르므로(실측 B/R 1.23~1.86 vs 1.10), 필름 모드는 실측 범위에 이
    // 상대 계수만 곱합니다.
    std::array<float, 3> range_factor{};
    std::array<float, 3> light_gain{};
};

// 번들 컬러 네거티브 스톡 마스크 색도(Dmin 차, log10)의 중앙값입니다. 크롭 바깥 띠에서
// 광원과 베이스를 가르는 문턱의 근거입니다 — macOS `FilmBaseEstimator.colorNegativeMaskMedian`
// 과 같은 표·같은 중앙값(정렬 후 count/2 자리)입니다.
struct FilmStockMaskChroma final {
    double red_green{0.0};   // Dmin_G − Dmin_R
    double green_blue{0.0};  // Dmin_B − Dmin_G
    double red_blue{0.0};    // Dmin_B − Dmin_R
};

[[nodiscard]] FilmStockMaskChroma bundled_mask_chroma_median() noexcept;

// Returns the stock fallback Dmin (with a single light-source trim) and the
// stock Dmax channel ratio. Unknown identifiers deliberately fail closed.
[[nodiscard]] std::optional<FilmStockBasePreset> resolve_film_stock_base_preset(
    std::wstring_view film_stock_id,
    std::wstring_view light_source_profile_id,
    NegativeFilmType film_type) noexcept;

}  // namespace negaflow::imaging
