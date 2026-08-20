#include "negaflow/imaging/auto_negative_base_resolver.h"

#include "auto_negative_base_candidates.h"
#include "auto_negative_base_exclusion.h"
#include "auto_negative_base_fallback.h"
#include "film_base_sampling.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <optional>
#include <vector>

namespace negaflow::imaging {
namespace {

using namespace negaflow::imaging::auto_base_detail;

constexpr std::array<float, 3> color_fallback{0.86F, 0.68F, 0.50F};
constexpr std::array<float, 3> monochrome_fallback{0.80F, 0.80F, 0.80F};

using film_base_detail::BaseMeasurement;
using film_base_detail::SampleGrid;
using film_base_detail::SampleGridGeometry;
using film_base_detail::candidate_indices;
using film_base_detail::candidate_luma_peak;
using film_base_detail::coherent_measurement;
using film_base_detail::connected_component_base;
using film_base_detail::finite_rgb;
using film_base_detail::has_compatible_layout;
using film_base_detail::is_component_candidate;
using film_base_detail::luma_of;
using film_base_detail::make_sample_grid;
using film_base_detail::make_sample_grid_geometry;
using film_base_detail::median;
using film_base_detail::percentile;
using film_base_detail::upper_median;

[[nodiscard]] std::array<float, 3> fallback_for(const NegativeFilmType film_type) noexcept {
    return film_type == NegativeFilmType::black_and_white ? monochrome_fallback : color_fallback;
}

[[nodiscard]] std::array<float, 3> narrow_measurement(const BaseMeasurement& measurement) noexcept {
    return {
        static_cast<float>(measurement[0]),
        static_cast<float>(measurement[1]),
        static_cast<float>(measurement[2]),
    };
}

}  // namespace

AutoNegativeBaseResult resolve_auto_negative_base(
    const WorkingImage& image,
    const NegativeFilmType film_type) noexcept {
    AutoNegativeBaseResult result{};
    if (!has_compatible_layout(image)) {
        return result;
    }

    result.status = AutoNegativeBaseStatus::ok;
    result.dmin = fallback_for(film_type);
    const auto with_chromogenic_fallback = [&image, film_type](const AutoNegativeBaseResult resolved) {
        if (film_type != NegativeFilmType::black_and_white ||
            resolved.status != AutoNegativeBaseStatus::ok) {
            return resolved;
        }
        const double maximum = std::max(
            static_cast<double>(resolved.dmin[0]),
            std::max(
                static_cast<double>(resolved.dmin[1]),
                static_cast<double>(resolved.dmin[2])));
        const double minimum = std::min(
            static_cast<double>(resolved.dmin[0]),
            std::min(
                static_cast<double>(resolved.dmin[1]),
                static_cast<double>(resolved.dmin[2])));
        // macOS's estimator returns nil when neutral-base measurement fails.  Its
        // fallback constant is applied only after the chromogenic retry, so the
        // Windows fallback must not be mistaken for a measured neutral base here.
        if (resolved.source != AutoNegativeBaseSource::fallback &&
            (minimum <= 1.0e-6 || maximum / minimum <= 1.25)) {
            return resolved;
        }
        const AutoNegativeBaseResult chromogenic = resolve_auto_negative_base(image, NegativeFilmType::color);
        return chromogenic.status == AutoNegativeBaseStatus::ok &&
                chromogenic.source != AutoNegativeBaseSource::fallback
            ? chromogenic
            : resolved;
    };
    if (image.width <= 4U || image.height <= 4U) {
        return result;
    }

    try {
        const std::optional<SampleGrid> grid = make_sample_grid(image);
        if (!grid.has_value()) {
            return result;
        }
        const auto apply = [&result](const FilmBaseMeasurement& measurement,
                                     const AutoNegativeBaseSource source) {
            result.dmin = narrow_measurement(measurement.rgb);
            result.source = source;
            result.diagnostics = measurement.diagnostics;
        };
        // 실험 knob: NEGA_BASE_SKIP_CC=1 이면 연결 성분을 건너뛰고 폴백 경로를 봅니다.
        // macOS 표본 그리드에서 성분이 최소 크기를 못 넘겨 폴백으로 갔는지 재기 위한 자리입니다.
        std::size_t skip_length = 0U;
        const bool skip_component =
            getenv_s(&skip_length, nullptr, 0U, "NEGA_BASE_SKIP_CC") == 0 && skip_length > 0U;
        if (const std::optional<FilmBaseMeasurement> component =
                skip_component ? std::nullopt : connected_component_base(*grid, film_type)) {
            apply(*component, AutoNegativeBaseSource::connected_component);
            return with_chromogenic_fallback(result);
        }
        const std::optional<std::vector<bool>> exclusion = non_film_exclusion(*grid, film_type);
        const std::vector<bool>* excluded = exclusion.has_value() ? &*exclusion : nullptr;
        const std::optional<FilmBaseMeasurement> edge =
            continuous_border_base(*grid, film_type, excluded);
        const std::optional<FilmBaseMeasurement> distributed =
            distributed_base(*grid, film_type, excluded);
        if (edge.has_value() && distributed.has_value()) {
            const double edge_luma =
                (edge->rgb[0] + edge->rgb[1] + edge->rgb[2]) / 3.0;
            const double distributed_luma =
                (distributed->rgb[0] + distributed->rgb[1] + distributed->rgb[2]) / 3.0;
            const bool use_edge = edge_luma >= distributed_luma * 0.85;
            apply(
                use_edge ? *edge : *distributed,
                use_edge
                    ? AutoNegativeBaseSource::continuous_border
                    : AutoNegativeBaseSource::distributed_mask);
            return with_chromogenic_fallback(result);
        }
        if (edge.has_value()) {
            apply(*edge, AutoNegativeBaseSource::continuous_border);
            return with_chromogenic_fallback(result);
        }
        if (distributed.has_value()) {
            apply(*distributed, AutoNegativeBaseSource::distributed_mask);
            return with_chromogenic_fallback(result);
        }
        if (const std::optional<FilmBaseMeasurement> strip =
                strip_fallback_base(*grid, film_type, excluded)) {
            apply(*strip, AutoNegativeBaseSource::strip_fallback);
            return with_chromogenic_fallback(result);
        }
        if (const std::optional<BaseMeasurement> scene_edge =
                scene_edge_fallback_base(image, film_type)) {
            result.dmin = narrow_measurement(*scene_edge);
            result.source = AutoNegativeBaseSource::scene_edge;
        }
    } catch (...) {
        // The documented fallback is preferable to allowing an allocation failure to cross a
        // noexcept ABI boundary. It remains distinguishable from a manual base in request mode.
    }
    return with_chromogenic_fallback(result);
}

const char* auto_negative_base_status_name(const AutoNegativeBaseStatus status) noexcept {
    switch (status) {
        case AutoNegativeBaseStatus::ok:
            return "ok";
        case AutoNegativeBaseStatus::invalid_image:
            return "invalid_image";
    }
    return "unknown_auto_negative_base_status";
}


}  // namespace negaflow::imaging
