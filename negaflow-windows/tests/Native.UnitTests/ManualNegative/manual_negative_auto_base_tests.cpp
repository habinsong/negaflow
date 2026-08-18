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

void test_auto_negative_base_resolution() {
    const auto auto_color = negaflow::imaging::resolve_auto_negative_base(
        make_auto_base_image({0.72F, 0.54F, 0.34F, 1.0F}),
        negaflow::imaging::NegativeFilmType::color);
    expect(
        auto_color.status == negaflow::imaging::AutoNegativeBaseStatus::ok &&
            auto_color.source == negaflow::imaging::AutoNegativeBaseSource::connected_component,
        "auto color base resolves from the linear connected component");
    expect(
        std::abs(auto_color.dmin[0] - 0.72F) < 1.0e-5F &&
            std::abs(auto_color.dmin[1] - 0.54F) < 1.0e-5F &&
            std::abs(auto_color.dmin[2] - 0.34F) < 1.0e-5F,
        "auto color base retains the measured orange transmission");

    const auto affine_auto_base = negaflow::imaging::resolve_auto_negative_base(
        make_affine_auto_base_image(),
        negaflow::imaging::NegativeFilmType::color);
    expect(
        affine_auto_base.source ==
                negaflow::imaging::AutoNegativeBaseSource::connected_component &&
            std::abs(affine_auto_base.dmin[0] - 0.64F) < 1.0e-6F &&
            std::abs(affine_auto_base.dmin[1] - 0.48F) < 1.0e-6F &&
            std::abs(affine_auto_base.dmin[2] - 0.32F) < 1.0e-6F,
        "auto base grid uses one uniform pixel-centre bilinear affine sample for every path");

    auto component_with_backlight = make_auto_base_image({0.62F, 0.45F, 0.25F, 1.0F});
    for (std::uint32_t row = 5U; row < 11U; ++row) {
        for (std::uint32_t column = 28U; column < 36U; ++column) {
            component_with_backlight.pixels[static_cast<std::size_t>(row) * component_with_backlight.width + column] =
                {0.95F, 0.95F, 0.95F, 1.0F};
        }
    }
    const auto auto_component = negaflow::imaging::resolve_auto_negative_base(
        component_with_backlight,
        negaflow::imaging::NegativeFilmType::color);
    expect(
        auto_component.source == negaflow::imaging::AutoNegativeBaseSource::connected_component &&
            std::abs(auto_component.dmin[0] - 0.62F) < 1.0e-5F &&
            std::abs(auto_component.dmin[1] - 0.45F) < 1.0e-5F &&
            std::abs(auto_component.dmin[2] - 0.25F) < 1.0e-5F,
        "connected component excludes a hard-bright backlight region");

    const auto coherent_component = negaflow::imaging::resolve_auto_negative_base(
        make_auto_base_component_with_luma_outliers(),
        negaflow::imaging::NegativeFilmType::color);
    expect(
        coherent_component.source ==
                negaflow::imaging::AutoNegativeBaseSource::connected_component &&
            std::abs(coherent_component.dmin[0] - 0.7212F) < 1.0e-6F &&
            std::abs(coherent_component.dmin[1] - 0.5406F) < 1.0e-6F &&
            std::abs(coherent_component.dmin[2] - 0.4003F) < 1.0e-6F,
        "connected component rejects luma outliers before channel medians");

    const auto ordered_component = negaflow::imaging::resolve_auto_negative_base(
        make_auto_base_component_order_image(),
        negaflow::imaging::NegativeFilmType::color);
    expect(
        ordered_component.source ==
                negaflow::imaging::AutoNegativeBaseSource::connected_component &&
            std::abs(ordered_component.dmin[0] - 0.755F) < 1.0e-6F &&
            std::abs(ordered_component.dmin[1] - 0.70F) < 1.0e-6F &&
            std::abs(ordered_component.dmin[2] - 0.645F) < 1.0e-6F,
        "connected component tests only the first lower mode with the macOS upper R-B median");

    const auto double_luma_boundary = negaflow::imaging::resolve_auto_negative_base(
        make_auto_base_double_luma_boundary_image(),
        negaflow::imaging::NegativeFilmType::color);
    expect(
        double_luma_boundary.source ==
                negaflow::imaging::AutoNegativeBaseSource::strip_fallback &&
            double_luma_boundary.dmin == std::array<float, 3>{0.005F, 0.005F, 0.005F},
        "Auto base promotes Float RGB to Double before the color-candidate luma threshold");

    auto component_with_colored_backlight = make_auto_base_image({0.005F, 0.005F, 0.005F, 1.0F});
    for (std::uint32_t row = 3U; row < 13U; ++row) {
        for (std::uint32_t column = 3U; column < 22U; ++column) {
            component_with_colored_backlight.pixels[
                static_cast<std::size_t>(row) * component_with_colored_backlight.width + column] =
                {0.70F, 0.64F, 0.58F, 1.0F};
        }
        for (std::uint32_t column = 40U; column < 59U; ++column) {
            component_with_colored_backlight.pixels[
                static_cast<std::size_t>(row) * component_with_colored_backlight.width + column] =
                {0.45F, 0.32F, 0.16F, 1.0F};
        }
    }
    const auto auto_demoted_component = negaflow::imaging::resolve_auto_negative_base(
        component_with_colored_backlight,
        negaflow::imaging::NegativeFilmType::color);
    expect(
        auto_demoted_component.source == negaflow::imaging::AutoNegativeBaseSource::connected_component &&
            std::abs(auto_demoted_component.dmin[0] - 0.45F) < 1.0e-5F &&
            std::abs(auto_demoted_component.dmin[1] - 0.32F) < 1.0e-5F &&
            std::abs(auto_demoted_component.dmin[2] - 0.16F) < 1.0e-5F,
        "color backlight component is demoted below the orange film base");

    auto masked_strip_image = make_auto_base_image({0.005F, 0.005F, 0.005F, 1.0F});
    for (negaflow::core::Rgba32F& pixel : masked_strip_image.pixels) {
        pixel = {0.005F, 0.005F, 0.005F, 1.0F};
    }
    for (const std::uint32_t column : {0U, 1U, 2U, 3U, 4U, 5U, 6U, 7U, 8U, 9U, 10U,
                                       20U, 21U, 22U, 23U, 24U, 25U, 26U, 27U, 28U, 29U, 30U,
                                       40U, 41U, 42U, 43U, 44U, 45U, 46U, 47U, 48U, 49U, 50U}) {
        masked_strip_image.pixels[column] = {0.70F, 0.50F, 0.30F, 1.0F};
    }
    for (std::uint32_t column = 54U; column < 64U; ++column) {
        masked_strip_image.pixels[column] = {0.82F, 0.80F, 0.78F, 1.0F};
    }
    const auto masked_strip = negaflow::imaging::resolve_auto_negative_base(
        masked_strip_image,
        negaflow::imaging::NegativeFilmType::color);
    expect(
        masked_strip.source == negaflow::imaging::AutoNegativeBaseSource::strip_fallback &&
            std::abs(masked_strip.dmin[0] - (23.195F / 52.0F)) < 1.0e-5F &&
            std::abs(masked_strip.dmin[1] - (16.595F / 52.0F)) < 1.0e-5F &&
            std::abs(masked_strip.dmin[2] - (9.995F / 52.0F)) < 1.0e-5F,
        "non-film mask is applied before the grid strip fallback");

    auto continuous_border_image = make_auto_base_image({0.005F, 0.005F, 0.005F, 1.0F});
    for (negaflow::core::Rgba32F& pixel : continuous_border_image.pixels) {
        pixel = {0.005F, 0.005F, 0.005F, 1.0F};
    }
    for (const std::uint32_t column : {0U, 1U, 2U, 3U, 4U, 5U, 6U, 7U, 8U, 9U,
                                       10U, 11U, 12U, 13U, 14U, 15U, 16U, 17U, 18U, 19U,
                                       22U, 23U, 24U, 25U, 26U, 27U, 28U, 29U, 30U, 31U,
                                       32U, 33U, 34U, 35U, 36U, 37U, 38U, 39U, 40U, 41U,
                                       44U, 45U, 46U, 47U, 48U, 49U, 50U, 51U, 52U, 53U,
                                       54U, 55U, 56U, 57U, 58U, 59U, 60U, 61U, 62U, 63U}) {
        continuous_border_image.pixels[column] = {0.70F, 0.50F, 0.30F, 1.0F};
    }
    const auto continuous_border = negaflow::imaging::resolve_auto_negative_base(
        continuous_border_image,
        negaflow::imaging::NegativeFilmType::color);
    expect(
        continuous_border.source == negaflow::imaging::AutoNegativeBaseSource::continuous_border &&
            continuous_border.dmin == std::array<float, 3>{0.70F, 0.50F, 0.30F},
        "continuous border fallback handles separated base fragments");

    const auto exact_edge_fraction = negaflow::imaging::resolve_auto_negative_base(
        make_auto_base_edge_fraction_image(),
        negaflow::imaging::NegativeFilmType::color);
    expect(
        exact_edge_fraction.source ==
                negaflow::imaging::AutoNegativeBaseSource::continuous_border &&
            exact_edge_fraction.dmin == std::array<float, 3>{0.70F, 0.50F, 0.30F},
        "Auto base uses macOS Double edge fractions at integral boundaries");

    auto distributed_image = make_auto_base_image({0.005F, 0.005F, 0.005F, 1.0F});
    for (negaflow::core::Rgba32F& pixel : distributed_image.pixels) {
        pixel = {0.005F, 0.005F, 0.005F, 1.0F};
    }
    std::uint32_t high_count = 0U;
    for (std::uint32_t row = 4U; row < 12U; ++row) {
        for (std::uint32_t column = 0U; column < 16U; ++column) {
            if ((row + column) % 2U != 0U) { continue; }
            distributed_image.pixels[static_cast<std::size_t>(row) * distributed_image.width + column] =
                high_count++ < 32U ? negaflow::core::Rgba32F{0.70F, 0.50F, 0.30F, 1.0F}
                                  : negaflow::core::Rgba32F{0.40F, 0.28F, 0.14F, 1.0F};
        }
    }
    const auto distributed = negaflow::imaging::resolve_auto_negative_base(
        distributed_image,
        negaflow::imaging::NegativeFilmType::color);
    expect(
        distributed.source == negaflow::imaging::AutoNegativeBaseSource::distributed_mask &&
            distributed.dmin == std::array<float, 3>{0.70F, 0.50F, 0.30F},
        "distributed fallback selects the coherent bright candidate mask");

    const auto auto_bw = negaflow::imaging::resolve_auto_negative_base(
        make_auto_base_image({0.70F, 0.68F, 0.69F, 1.0F}),
        negaflow::imaging::NegativeFilmType::black_and_white);
    expect(
        auto_bw.status == negaflow::imaging::AutoNegativeBaseStatus::ok &&
            auto_bw.source == negaflow::imaging::AutoNegativeBaseSource::connected_component,
        "auto B&W base accepts a neutral component");

    const auto chromogenic_bw = negaflow::imaging::resolve_auto_negative_base(
        make_auto_base_image({0.72F, 0.54F, 0.34F, 1.0F}),
        negaflow::imaging::NegativeFilmType::black_and_white);
    expect(
        chromogenic_bw.source == negaflow::imaging::AutoNegativeBaseSource::connected_component &&
            std::abs(chromogenic_bw.dmin[0] - 0.72F) < 1.0e-5F &&
            std::abs(chromogenic_bw.dmin[1] - 0.54F) < 1.0e-5F &&
            std::abs(chromogenic_bw.dmin[2] - 0.34F) < 1.0e-5F,
        "chromogenic B&W retries the color base estimator for a tinted result");

    const auto scene_edge = negaflow::imaging::resolve_auto_negative_base(
        make_scene_edge_fallback_image(),
        negaflow::imaging::NegativeFilmType::color);
    expect(
        scene_edge.source == negaflow::imaging::AutoNegativeBaseSource::scene_edge &&
            scene_edge.dmin == std::array<float, 3>{0.48F, 0.32F, 0.16F},
        "scene-edge fallback measures sparse edge base candidates before constants");

    const auto affine_scene_edge = negaflow::imaging::resolve_auto_negative_base(
        make_affine_scene_edge_fallback_image(),
        negaflow::imaging::NegativeFilmType::color);
    expect(
        affine_scene_edge.source == negaflow::imaging::AutoNegativeBaseSource::scene_edge &&
            std::abs(affine_scene_edge.dmin[0] - 0.48F) < 1.0e-6F &&
            std::abs(affine_scene_edge.dmin[1] - 0.32F) < 1.0e-6F &&
            std::abs(affine_scene_edge.dmin[2] - 0.16F) < 1.0e-6F,
        "scene-edge fallback uses the macOS uniform pixel-centre bilinear affine sample");

    auto clipped_auto_image = make_auto_base_image({0.98F, 0.98F, 0.98F, 1.0F});
    for (negaflow::core::Rgba32F& pixel : clipped_auto_image.pixels) {
        pixel = {0.98F, 0.98F, 0.98F, 1.0F};
    }
    const auto auto_fallback = negaflow::imaging::resolve_auto_negative_base(
        clipped_auto_image,
        negaflow::imaging::NegativeFilmType::color);
    expect(
        auto_fallback.status == negaflow::imaging::AutoNegativeBaseStatus::ok &&
            auto_fallback.source == negaflow::imaging::AutoNegativeBaseSource::fallback &&
            auto_fallback.dmin == std::array<float, 3>{0.86F, 0.68F, 0.50F},
        "filmless edge falls back to the macOS color base");

    const auto bw_auto_fallback = negaflow::imaging::resolve_auto_negative_base(
        clipped_auto_image,
        negaflow::imaging::NegativeFilmType::black_and_white);
    expect(
        bw_auto_fallback.status == negaflow::imaging::AutoNegativeBaseStatus::ok &&
            bw_auto_fallback.source == negaflow::imaging::AutoNegativeBaseSource::fallback &&
            bw_auto_fallback.dmin == std::array<float, 3>{0.80F, 0.80F, 0.80F},
        "filmless B&W retries chromogenic measurement before retaining its neutral fallback");

    auto invalid_auto_image = make_auto_base_image({0.72F, 0.54F, 0.34F, 1.0F});
    invalid_auto_image.stride_pixels = 1U;
    expect(
        negaflow::imaging::resolve_auto_negative_base(
            invalid_auto_image,
            negaflow::imaging::NegativeFilmType::color).status ==
            negaflow::imaging::AutoNegativeBaseStatus::invalid_image,
        "invalid auto base input is rejected");
}

}  // namespace manual_negative_tests
