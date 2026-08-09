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
    std::array<float, 3> light_gain{};
};

// Returns the stock fallback Dmin (with a single light-source trim) and the
// stock Dmax channel ratio. Unknown identifiers deliberately fail closed.
[[nodiscard]] std::optional<FilmStockBasePreset> resolve_film_stock_base_preset(
    std::wstring_view film_stock_id,
    std::wstring_view light_source_profile_id,
    NegativeFilmType film_type) noexcept;

}  // namespace negaflow::imaging
