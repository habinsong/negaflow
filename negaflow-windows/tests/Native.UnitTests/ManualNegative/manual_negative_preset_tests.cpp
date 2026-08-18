#include "manual_negative_test_support.h"

#include "negaflow/core/negative_inversion.h"
#include "negaflow/imaging/auto_negative_base_resolver.h"
#include "negaflow/imaging/film_stock_base_resolver.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <limits>
#include <utility>
#include <vector>

namespace manual_negative_tests {

void test_film_stock_presets() {
    using negaflow::imaging::AutoNegativeBaseSource;
    expect(
        negaflow::imaging::confident_auto_negative_base_source(
            AutoNegativeBaseSource::connected_component) &&
            negaflow::imaging::confident_auto_negative_base_source(
                AutoNegativeBaseSource::continuous_border) &&
            negaflow::imaging::confident_auto_negative_base_source(
                AutoNegativeBaseSource::distributed_mask),
        "preset base accepts every confident measured source");
    expect(
        !negaflow::imaging::confident_auto_negative_base_source(
            AutoNegativeBaseSource::scene_edge) &&
            !negaflow::imaging::confident_auto_negative_base_source(
                AutoNegativeBaseSource::strip_fallback) &&
            !negaflow::imaging::confident_auto_negative_base_source(
                AutoNegativeBaseSource::fallback),
        "preset base rejects compatibility and constant fallbacks");

    const auto portra = negaflow::imaging::resolve_film_stock_base_preset(
        L"kodak-portra-400",
        L"warm-led",
        negaflow::imaging::NegativeFilmType::color);
    expect(portra.has_value(), "known bundled film stock resolves");
    if (portra) {
        expect(
            std::abs(portra->dmin[0] - std::pow(10.0F, -0.21F)) < 1.0e-5F &&
                std::abs(portra->dmin[1] - std::pow(10.0F, -0.62F)) < 1.0e-5F &&
                std::abs(portra->dmin[2] - std::pow(10.0F, -0.82F)) < 1.0e-5F,
            "stock fallback uses the documented Dmin transmission");
        expect(
            portra->dmax_normalized == std::array<float, 3>{2.04F, 2.23F, 2.23F},
            "stock response uses Dmax minus Dmin per channel");
        expect(
            portra->light_gain == std::array<float, 3>{1.06F, 1.0F, 0.92F},
            "selected light source is prepared for one application");
    }
    const auto portra_bw = negaflow::imaging::resolve_film_stock_base_preset(
        L"kodak-portra-400",
        L"warm-led",
        negaflow::imaging::NegativeFilmType::black_and_white);
    expect(
        portra_bw && portra_bw->light_gain == std::array<float, 3>{1.0F, 1.0F, 1.0F},
        "B&W Film base ignores light-source gain");
    expect(
        !negaflow::imaging::resolve_film_stock_base_preset(
            L"not-a-stock", L"neutral", negaflow::imaging::NegativeFilmType::color),
        "unknown stock fails closed");
    expect(
        !negaflow::imaging::resolve_film_stock_base_preset(
            L"kodak-portra-400", L"not-a-light", negaflow::imaging::NegativeFilmType::color),
        "unknown light source fails closed");
}

}  // namespace manual_negative_tests
