#include "negaflow/imaging/auto_negative_base_resolver.h"

#include "auto_negative_base_candidates.h"
#include "auto_negative_base_exclusion.h"
#include "auto_negative_base_fallback.h"
#include "auto_negative_base_rebate.h"
#include "film_base_sampling.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <optional>
#include <utility>
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
using film_base_detail::BaseSearchScope;
using film_base_detail::excluding_interior;
using film_base_detail::keeping_interior;
using film_base_detail::ring_mask_chroma;
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

// 이 지점을 넘으면 **틀렸다고 볼 이유가 있을 때만** 한 화소라도 더 읽습니다. 정상 20 장이
// 0.44~2.32%, 잘못 고른 2 장이 10.6~11.0% 로 갈립니다(실측 22 장).
constexpr double rebate_gate_fraction = 0.05;

/// <param name="grid">
/// 축소본을 **한 번만** 짓기 위한 자리입니다. 뒤이어 도는 문지기가 같은 격자를 보므로,
/// 여기서 지어 두고 넘겨줍니다 — 따로 지으면 18 Mpx 한 장에 39 ms 가 더 붙습니다(실측).
/// </param>
// 확신 있는 측정만 찾습니다(macOS `confidentOnly: true`). 띠 폴백·장면 가장자리 추정은 하지
// 않습니다 — 그것은 프레임 전체 탐색의 몫입니다. 띠는 띠의 비필름 마스크를, 사진은 마스크 없이
// 봅니다(사진은 전부 필름입니다).
[[nodiscard]] std::optional<std::pair<FilmBaseMeasurement, AutoNegativeBaseSource>> confident_base(
    const SampleGrid& grid,
    const NegativeFilmType film_type,
    const BaseSearchScope scope,
    const bool demotes) {
    if (const std::optional<FilmBaseMeasurement> component =
            connected_component_base(grid, film_type, scope, demotes)) {
        return std::pair{*component, AutoNegativeBaseSource::connected_component};
    }
    const std::optional<std::vector<bool>> exclusion = scope == BaseSearchScope::ring
        ? non_film_exclusion(grid, film_type)
        : std::nullopt;
    const std::vector<bool>* excluded = exclusion.has_value() ? &*exclusion : nullptr;
    const std::optional<FilmBaseMeasurement> edge = continuous_border_base(grid, film_type, excluded);
    const std::optional<FilmBaseMeasurement> distributed = distributed_base(grid, film_type, excluded);
    if (edge.has_value() && distributed.has_value()) {
        const double edge_luma = (edge->rgb[0] + edge->rgb[1] + edge->rgb[2]) / 3.0;
        const double distributed_luma =
            (distributed->rgb[0] + distributed->rgb[1] + distributed->rgb[2]) / 3.0;
        return edge_luma >= distributed_luma * 0.85
            ? std::pair{*edge, AutoNegativeBaseSource::continuous_border}
            : std::pair{*distributed, AutoNegativeBaseSource::distributed_mask};
    }
    if (edge.has_value()) {
        return std::pair{*edge, AutoNegativeBaseSource::continuous_border};
    }
    if (distributed.has_value()) {
        return std::pair{*distributed, AutoNegativeBaseSource::distributed_mask};
    }
    return std::nullopt;
}

[[nodiscard]] AutoNegativeBaseResult measured_result(
    const std::pair<FilmBaseMeasurement, AutoNegativeBaseSource>& found) noexcept {
    AutoNegativeBaseResult result{};
    result.status = AutoNegativeBaseStatus::ok;
    result.dmin = narrow_measurement(found.first.rgb);
    result.source = found.second;
    result.diagnostics = found.first.diagnostics;
    return result;
}

[[nodiscard]] double luma_of_dmin(const std::array<float, 3>& dmin) noexcept {
    return (static_cast<double>(dmin[0]) + static_cast<double>(dmin[1]) + static_cast<double>(dmin[2])) / 3.0;
}

// 고른 값이 물리적으로 말이 되는지 보고, 안 되면 리베이트 띠에서 원본 해상도로 다시 잽니다.
// 받아들이지 않으면 기존 값이 그대로 남습니다(macOS `rescuedWithRebate`).
[[nodiscard]] AutoNegativeBaseResult rescued_with_rebate(
    const WorkingImage& image,
    const SampleGrid& searched,
    const NegativeFilmType film_type,
    AutoNegativeBaseResult result,
    const bool ring_scope) noexcept {
    try {
        result.brighter_than_base =
            auto_base_detail::brighter_than_base_fraction(searched, result.dmin);
        // 띠 찾기는 축소본 위에서만 도는 선형 두 번이라 늘 돌려도 쌉니다. 원본을 다시 읽을지는
        // 그 안에서 정합니다 — 문지기가 열렸거나, 띠가 뭉개질 만큼 얇을 때만입니다.
        const std::optional<BaseMeasurement> rebate = auto_base_detail::rebate_base(
            image, searched, film_type, result.brighter_than_base > rebate_gate_fraction);
        if (!rebate.has_value() ||
            !auto_base_detail::accept_rebate_base(*rebate, result.dmin)) {
            return result;
        }
        // 띠에서는 베이스를 색도 증거로 골랐습니다. 리베이트 띠는 베이스 그 자체라 색도가
        // 같아야 합니다 — 마스크 색도만큼 덜 오렌지인 "더 밝은 띠" 는 광원입니다(바꾸지 않습니다).
        if (ring_scope && film_type == NegativeFilmType::color) {
            const auto log_red_blue = [](const double red, const double blue) {
                return std::log10(std::max(red, 1.0e-5) / std::max(blue, 1.0e-5));
            };
            if (log_red_blue((*rebate)[0], (*rebate)[2]) <
                log_red_blue(result.dmin[0], result.dmin[2]) - ring_mask_chroma().red_blue) {
                return result;
            }
        }
        result.dmin = narrow_measurement(*rebate);
        result.rebate_rescued = true;
    } catch (...) {
        // 구조길이 실패해도 기존 값은 그대로입니다. 고치려다 더 나쁘게 만들지 않습니다.
    }
    return result;
}

// 베이스 판정의 모순 문턱 — `contradicting_fraction` 의 실측(정상 0~0.8%, 모순 7.1%~).
constexpr double contradiction_fraction = 0.02;

// 고른 값보다 뚜렷이 밝은 필름이 있으면(모순) 필름에서 가장 밝은 5%(분산 샘플러)로 올립니다.
// 베이스가 화면에 없는 컷에서 성분 검출은 결이 있는 얇은 면 — 이웃 15% 문턱에 걸려 조각납니다 —
// 을 놓치고 더 어두운 매끈한 면을 고릅니다(2026-10-15 macOS 실측: 같은 롤 베이스 0.23/0.096/0.068,
// 고른 값 0.104/0.051/0.032, 그보다 밝은 필름 11% 가 반전에서 검정으로 잘렸습니다).
[[nodiscard]] AutoNegativeBaseResult lifted_to_film_envelope(
    const SampleGrid& grid,
    const NegativeFilmType film_type,
    AutoNegativeBaseResult result,
    const AnalysisRegion* interior_of,
    const std::vector<bool>* excluded) {
    if (auto_base_detail::contradicting_fraction(grid, result.dmin, film_type, interior_of, excluded) <=
        contradiction_fraction) {
        return result;
    }
    const std::optional<FilmBaseMeasurement> envelope = distributed_base(grid, film_type, excluded);
    if (!envelope.has_value() ||
        luma_of_dmin(narrow_measurement(envelope->rgb)) <= luma_of_dmin(result.dmin)) {
        return result;
    }
    result.dmin = narrow_measurement(envelope->rgb);
    result.source = AutoNegativeBaseSource::distributed_mask;
    result.diagnostics = envelope->diagnostics;
    return result;
}

// `candidate` 가 `film` 을 비춘 광원처럼 보이는가. 필름 = 광원 × 마스크 × 장면 염료라, 광원이면
// 필름이 마스크 색도(띠 강등과 같은 문턱)만큼 두 축 모두 더 오렌지입니다(macOS `looksLikeLight`).
[[nodiscard]] bool looks_like_light(const std::array<float, 3>& candidate, const std::array<float, 3>& film) {
    const auto log_ratio = [](const float a, const float b) {
        return std::log10(std::max(static_cast<double>(a), 1.0e-5) / std::max(static_cast<double>(b), 1.0e-5));
    };
    const film_base_detail::RingMaskChroma mask = ring_mask_chroma();
    return log_ratio(film[0], film[1]) - log_ratio(candidate[0], candidate[1]) >= mask.red_green &&
        log_ratio(film[1], film[2]) - log_ratio(candidate[1], candidate[2]) >= mask.green_blue;
}

// 크롭이 있을 때의 베이스(macOS `estimateAroundCrop`). 디카 스캔은 원본에 퍼포레이션·백라이트·
// 홀더가 함께 찍혀 프레임 전체를 뒤지면 광원을 베이스로 잡기 쉽습니다 — 그래서 크롭이 있으면 프레임
// 전체로 가지 않습니다.
//  1. 크롭 바깥 띠(리베이트)에서 찾고, 그 값이 크롭 안 사진과 모순이 없으면 씁니다.
//  2. 모순이면 띠의 광원 강등이 틀렸을 수 있습니다 — 강등 없이 띠에서 가장 밝은 성분을 보고, 사진과
//     모순이 없고 광원처럼 보이지도 않으면 씁니다.
//  3. 띠에 베이스가 없으면(크롭이 리베이트를 잘라 냄) 크롭 안 사진에서 가장 얇은 필름 면을 씁니다.
// 셋 다 없을 때만 nullopt — 그때는 예전처럼 프레임 전체에서 찾습니다.
[[nodiscard]] std::optional<AutoNegativeBaseResult> resolve_around_crop(
    const WorkingImage& image,
    const NegativeFilmType film_type,
    const SampleGrid& grid,
    const AnalysisRegion& region) {
    const SampleGrid ring = excluding_interior(grid, region);
    const auto ring_answer = [&](const bool demotes) -> std::optional<AutoNegativeBaseResult> {
        const auto found = confident_base(ring, film_type, BaseSearchScope::ring, demotes);
        if (!found.has_value()) {
            return std::nullopt;
        }
        return rescued_with_rebate(image, ring, film_type, measured_result(*found), true);
    };
    const auto contradicted = [&](const AutoNegativeBaseResult& candidate) {
        return auto_base_detail::contradicting_fraction(grid, candidate.dmin, film_type, &region, nullptr) >
            contradiction_fraction;
    };
    // 사진 안 탐색은 띠가 실패했을 때만 돕니다(대부분의 프레임은 띠에서 끝납니다).
    std::optional<std::optional<AutoNegativeBaseResult>> cached_photo;
    const auto photo = [&]() -> std::optional<AutoNegativeBaseResult> {
        if (!cached_photo.has_value()) {
            const SampleGrid photo_grid = keeping_interior(grid, region);
            const auto found = confident_base(photo_grid, film_type, BaseSearchScope::photo, true);
            cached_photo = found.has_value()
                ? std::optional{lifted_to_film_envelope(photo_grid, film_type, measured_result(*found), &region, nullptr)}
                : std::nullopt;
        }
        return *cached_photo;
    };
    const std::optional<AutoNegativeBaseResult> demoted = ring_answer(true);
    if (!demoted.has_value()) {
        return photo();
    }
    if (!contradicted(*demoted)) {
        return demoted;
    }
    // 2026-10-15 macOS 실측: 오른쪽 띠의 리베이트(0.34/0.158/0.092)를 광원으로 강등하고 짙은 장면
    // (0.11/0.032/0.012)을 골랐습니다 — 사진의 97% 가 그보다 밝았습니다.
    if (film_type == NegativeFilmType::color) {
        if (const std::optional<AutoNegativeBaseResult> top = ring_answer(false);
            top.has_value() && top->dmin != demoted->dmin && !contradicted(*top)) {
            const std::optional<AutoNegativeBaseResult> film = photo();
            if (!film.has_value() || !looks_like_light(top->dmin, film->dmin)) {
                return top;
            }
        }
    }
    return photo();
}

/// <param name="from_crop">
/// 크롭 영역에서 답이 나왔으면 참입니다 — 그 답은 리베이트 확인·모순 판정을 이미 거쳤습니다.
/// </param>
[[nodiscard]] AutoNegativeBaseResult resolve_without_rebate(
    const WorkingImage& image,
    const NegativeFilmType film_type,
    std::optional<SampleGrid>& grid,
    const std::optional<AnalysisRegion>& region,
    bool& from_crop) noexcept {
    from_crop = false;
    AutoNegativeBaseResult result{};
    if (!has_compatible_layout(image)) {
        return result;
    }

    result.status = AutoNegativeBaseStatus::ok;
    result.dmin = fallback_for(film_type);
    const auto with_chromogenic_fallback = [&image, film_type, &region](
                                               const AutoNegativeBaseResult resolved) {
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
        const AutoNegativeBaseResult chromogenic =
            resolve_auto_negative_base(image, NegativeFilmType::color, region);
        return chromogenic.status == AutoNegativeBaseStatus::ok &&
                chromogenic.source != AutoNegativeBaseSource::fallback
            ? chromogenic
            : resolved;
    };
    if (image.width <= 4U || image.height <= 4U) {
        return result;
    }

    try {
        if (!grid.has_value()) {
            grid = make_sample_grid(image);
        }
        if (!grid.has_value()) {
            return result;
        }
        const auto apply = [&result](const FilmBaseMeasurement& measurement,
                                     const AutoNegativeBaseSource source) {
            result.dmin = narrow_measurement(measurement.rgb);
            result.source = source;
            result.diagnostics = measurement.diagnostics;
        };
        if (region.has_value()) {
            if (const std::optional<AutoNegativeBaseResult> cropped =
                    resolve_around_crop(image, film_type, *grid, *region)) {
                from_crop = true;
                return with_chromogenic_fallback(*cropped);
            }
        }
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

}  // namespace

AutoNegativeBaseResult resolve_auto_negative_base(
    const WorkingImage& image,
    const NegativeFilmType film_type,
    const std::optional<AnalysisRegion>& region) noexcept {
    // 축소본은 기존 경로가 이미 지었습니다. 문지기가 그것을 그대로 봅니다.
    std::optional<SampleGrid> grid;
    bool from_crop = false;
    AutoNegativeBaseResult result = resolve_without_rebate(image, film_type, grid, region, from_crop);
    if (result.status != AutoNegativeBaseStatus::ok || !grid.has_value() || from_crop ||
        result.source == AutoNegativeBaseSource::fallback) {
        return result;
    }
    try {
        result = rescued_with_rebate(image, *grid, film_type, result, false);
        const std::optional<std::vector<bool>> exclusion = non_film_exclusion(*grid, film_type);
        return lifted_to_film_envelope(
            *grid, film_type, result, nullptr, exclusion.has_value() ? &*exclusion : nullptr);
    } catch (...) {
        // 구조길이 실패해도 기존 값은 그대로입니다. 고치려다 더 나쁘게 만들지 않습니다.
    }
    return result;
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
