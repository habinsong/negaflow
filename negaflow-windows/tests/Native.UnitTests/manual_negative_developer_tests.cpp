#include "negaflow/core/negative_inversion.h"
#include "negaflow/imaging/auto_negative_base_resolver.h"
#include "negaflow/imaging/film_stock_base_resolver.h"
#include "negaflow/imaging/manual_negative_developer.h"

#include <array>
#include <cstddef>
#include <cmath>
#include <iostream>
#include <limits>
#include <utility>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] bool pixels_equal(
    const negaflow::core::Rgba32F& left,
    const negaflow::core::Rgba32F& right) noexcept {
    return left.red == right.red && left.green == right.green &&
           left.blue == right.blue && left.alpha == right.alpha;
}

negaflow::imaging::WorkingImage make_working_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 2U;
    image.height = 1U;
    image.stride_pixels = 2U;
    image.pixels = {
        {0.72F, 0.32F, 0.15F, 1.0F},
        {0.12F, 0.08F, 0.04F, 0.5F},
    };
    return image;
}

negaflow::imaging::WorkingImage make_scene_working_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 64U;
    image.height = 16U;
    image.stride_pixels = image.width;
    image.pixels.resize(static_cast<std::size_t>(image.width) * image.height);
    for (std::uint32_t row = 0U; row < image.height; ++row) {
        for (std::uint32_t column = 0U; column < image.width; ++column) {
            const float density = column < 8U ? 1.10F : 0.55F;
            image.pixels[static_cast<std::size_t>(row) * image.width + column] = {
                0.80F * std::pow(10.0F, -density),
                0.60F * std::pow(10.0F, -(density * 0.90F)),
                0.40F * std::pow(10.0F, -(density * 0.80F)),
                1.0F,
            };
        }
    }
    return image;
}

negaflow::imaging::WorkingImage make_auto_base_image(
    const negaflow::core::Rgba32F& base) {
    negaflow::imaging::WorkingImage image{};
    image.width = 64U;
    image.height = 16U;
    image.stride_pixels = image.width;
    image.pixels.resize(static_cast<std::size_t>(image.width) * image.height);
    for (std::uint32_t row = 0U; row < image.height; ++row) {
        for (std::uint32_t column = 0U; column < image.width; ++column) {
            const bool edge = column < 4U || column + 4U >= image.width ||
                row < 2U || row + 2U >= image.height;
            image.pixels[static_cast<std::size_t>(row) * image.width + column] = edge
                ? base
                : negaflow::core::Rgba32F{0.20F, 0.12F, 0.06F, 1.0F};
        }
    }
    return image;
}

}  // namespace

int main() {
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

    negaflow::imaging::WorkingImage source = make_working_image();
    std::array<negaflow::core::Rgba32F, 2> expected{};
    const negaflow::core::NegativeInversionParameters reference_parameters{
        {0.72F, 0.32F, 0.15F},
        {1.55F, 1.55F, 1.55F},
    };
    const auto reference_status = negaflow::core::apply_negative_inversion(
        {source.pixels.data(), source.pixels.size(), 2U, 1U, 2U},
        {expected.data(), expected.size(), 2U, 1U, 2U},
        reference_parameters,
        negaflow::core::color_negative_print_response());
    expect(reference_status == negaflow::core::KernelStatus::ok, "reference inversion succeeds");

    const negaflow::imaging::ManualNegativeDevelopParameters parameters{
        {0.72F, 0.32F, 0.15F},
        negaflow::imaging::NegativeFilmType::color,
    };
    const auto developed = negaflow::imaging::develop_manual_negative(
        std::move(source),
        parameters);
    expect(
        developed.status == negaflow::imaging::ManualNegativeDevelopStatus::ok,
        "manual color negative development succeeds");
    expect(
        developed.info.dmax_normalized == std::array<float, 3>{1.55F, 1.55F, 1.55F},
        "color generic density range is fixed");
    expect(developed.image.pixels.size() == expected.size(), "developed pixel count");
    if (developed.image.pixels.size() == expected.size()) {
        expect(pixels_equal(developed.image.pixels[0], expected[0]), "first in-place pixel exact");
        expect(pixels_equal(developed.image.pixels[1], expected[1]), "second in-place pixel exact");
        expect(developed.image.pixels[1].alpha == 0.5F, "alpha is preserved in place");
    }

    const negaflow::imaging::ManualNegativeDevelopParameters clamped_parameters{
        {0.0F, 2.0F, 0.5F},
        negaflow::imaging::NegativeFilmType::black_and_white,
    };
    const auto clamped = negaflow::imaging::develop_manual_negative(
        make_working_image(),
        clamped_parameters);
    expect(
        clamped.status == negaflow::imaging::ManualNegativeDevelopStatus::ok &&
            clamped.info.applied_dmin == std::array<float, 3>{0.001F, 1.0F, 0.5F},
        "manual Dmin follows baseline clamp");
    expect(
        clamped.info.dmax_normalized == std::array<float, 3>{2.17F, 2.17F, 2.17F},
        "B&W generic density range is fixed");

    const negaflow::imaging::ManualNegativeDevelopParameters scene_parameters{
        {0.80F, 0.60F, 0.40F},
        negaflow::imaging::NegativeFilmType::color,
    };
    const auto scene = negaflow::imaging::develop_manual_negative(
        make_scene_working_image(),
        scene_parameters);
    expect(
        scene.status == negaflow::imaging::ManualNegativeDevelopStatus::ok,
        "scene-ranged manual development succeeds");
    expect(
        std::abs(scene.info.dmax_normalized[0] - 1.10F) < 1.0e-4F &&
            std::abs(scene.info.dmax_normalized[1] - 0.99F) < 1.0e-4F &&
            std::abs(scene.info.dmax_normalized[2] - 0.88F) < 1.0e-4F,
        "scene-ranged manual development uses the robust low percentile per channel");
    expect(
        scene.info.dmax_normalized[0] != scene.info.dmax_normalized[2],
        "color scene range retains per-channel density differences");

    negaflow::imaging::ManualNegativeDevelopParameters preset_parameters = scene_parameters;
    preset_parameters.use_preset_response = true;
    preset_parameters.preset_dmax_normalized = {2.04F, 2.23F, 2.23F};
    const auto preset_scene = negaflow::imaging::develop_manual_negative(
        make_scene_working_image(),
        preset_parameters);
    expect(
        preset_scene.status == negaflow::imaging::ManualNegativeDevelopStatus::ok &&
            preset_scene.info.dmax_normalized[0] < preset_scene.info.dmax_normalized[1] &&
            std::abs(preset_scene.info.dmax_normalized[1] - preset_scene.info.dmax_normalized[2]) < 1.0e-5F,
        "preset keeps the measured density scale and stock channel ratio");

    const auto scene_bw = negaflow::imaging::develop_manual_negative(
        make_scene_working_image(),
        {scene_parameters.dmin, negaflow::imaging::NegativeFilmType::black_and_white});
    expect(
        scene_bw.status == negaflow::imaging::ManualNegativeDevelopStatus::ok &&
            scene_bw.info.dmax_normalized[0] == scene_bw.info.dmax_normalized[1] &&
            scene_bw.info.dmax_normalized[1] == scene_bw.info.dmax_normalized[2],
        "B&W scene range remains neutral");

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

    auto invalid_auto_image = make_auto_base_image({0.72F, 0.54F, 0.34F, 1.0F});
    invalid_auto_image.stride_pixels = 1U;
    expect(
        negaflow::imaging::resolve_auto_negative_base(
            invalid_auto_image,
            negaflow::imaging::NegativeFilmType::color).status ==
            negaflow::imaging::AutoNegativeBaseStatus::invalid_image,
        "invalid auto base input is rejected");

    auto non_finite_parameters = parameters;
    non_finite_parameters.dmin[1] = std::numeric_limits<float>::quiet_NaN();
    const auto non_finite = negaflow::imaging::develop_manual_negative(
        make_working_image(),
        non_finite_parameters);
    expect(
        non_finite.status == negaflow::imaging::ManualNegativeDevelopStatus::invalid_parameter &&
            non_finite.image.pixels.empty(),
        "non-finite manual parameter publishes no pixels");

    auto malformed = make_working_image();
    malformed.stride_pixels = 1U;
    const auto failed = negaflow::imaging::develop_manual_negative(
        std::move(malformed),
        parameters);
    expect(
        failed.status == negaflow::imaging::ManualNegativeDevelopStatus::kernel_failed &&
            failed.info.kernel_status == negaflow::core::KernelStatus::invalid_stride &&
            failed.image.pixels.empty(),
        "invalid working layout publishes no pixels");

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"manual_negative_developer\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
