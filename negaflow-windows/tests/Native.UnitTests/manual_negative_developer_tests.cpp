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
#include <vector>

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

[[nodiscard]] bool images_equal(
    const std::vector<negaflow::core::Rgba32F>& left,
    const std::vector<negaflow::core::Rgba32F>& right) noexcept {
    if (left.size() != right.size()) {
        return false;
    }
    for (std::size_t index = 0U; index < left.size(); ++index) {
        if (!pixels_equal(left[index], right[index])) {
            return false;
        }
    }
    return true;
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

negaflow::imaging::WorkingImage make_affine_proxy_scene_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 640U;
    image.height = 65U;
    image.stride_pixels = image.width;
    image.pixels.resize(static_cast<std::size_t>(image.width) * image.height);
    for (std::uint32_t row = 0U; row < image.height; ++row) {
        for (std::uint32_t column = 0U; column < image.width; ++column) {
            image.pixels[static_cast<std::size_t>(row) * image.width + column] = {
                column % 2U == 0U ? 0.08F : 0.16F,
                row % 2U == 0U ? 0.08F : 0.16F,
                0.12F,
                1.0F,
            };
        }
    }
    return image;
}

negaflow::imaging::WorkingImage make_affine_auto_base_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 512U;
    image.height = 129U;
    image.stride_pixels = image.width;
    image.pixels.resize(static_cast<std::size_t>(image.width) * image.height);
    for (std::uint32_t row = 0U; row < image.height; ++row) {
        for (std::uint32_t column = 0U; column < image.width; ++column) {
            image.pixels[static_cast<std::size_t>(row) * image.width + column] = {
                column % 2U == 0U ? 0.56F : 0.72F,
                row % 2U == 0U ? 0.40F : 0.56F,
                0.32F,
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

negaflow::imaging::WorkingImage make_auto_base_component_with_luma_outliers() {
    negaflow::imaging::WorkingImage image{};
    image.width = 64U;
    image.height = 16U;
    image.stride_pixels = image.width;
    image.pixels.assign(
        static_cast<std::size_t>(image.width) * image.height,
        negaflow::core::Rgba32F{0.005F, 0.005F, 0.005F, 1.0F});

    std::size_t component_index = 0U;
    for (std::uint32_t row = 4U; row < 8U; ++row) {
        for (std::uint32_t column = 8U; column < 20U; ++column) {
            negaflow::core::Rgba32F pixel{};
            if (component_index < 24U) {
                pixel = {0.70F, 0.53F, 0.39F, 1.0F};
            } else if (component_index < 37U) {
                const float offset = static_cast<float>(component_index - 24U);
                pixel = {
                    0.72F + offset * 0.0002F,
                    0.54F + offset * 0.0001F,
                    0.40F + offset * 0.00005F,
                    1.0F,
                };
            } else {
                pixel = {0.77F, 0.59F, 0.45F, 1.0F};
            }
            image.pixels[static_cast<std::size_t>(row) * image.width + column] = pixel;
            ++component_index;
        }
    }
    return image;
}

negaflow::imaging::WorkingImage make_auto_base_component_order_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 64U;
    image.height = 16U;
    image.stride_pixels = image.width;
    image.pixels.assign(
        static_cast<std::size_t>(image.width) * image.height,
        negaflow::core::Rgba32F{0.005F, 0.005F, 0.005F, 1.0F});

    const auto fill_component = [&image](
                                    const std::uint32_t first_column,
                                    const float luma,
                                    const float lower_red_blue,
                                    const float upper_red_blue) {
        std::size_t component_index = 0U;
        for (std::uint32_t row = 2U; row < 6U; ++row) {
            for (std::uint32_t column = first_column; column < first_column + 6U; ++column) {
                const float red_blue = component_index < 12U
                    ? lower_red_blue
                    : upper_red_blue;
                image.pixels[static_cast<std::size_t>(row) * image.width + column] = {
                    luma + red_blue * 0.5F,
                    luma,
                    luma - red_blue * 0.5F,
                    1.0F,
                };
                ++component_index;
            }
        }
    };
    fill_component(2U, 0.70F, 0.08F, 0.14F);
    fill_component(14U, 0.50F, 0.12F, 0.12F);
    fill_component(26U, 0.35F, 0.22F, 0.22F);
    return image;
}

negaflow::imaging::WorkingImage make_auto_base_double_luma_boundary_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 32U;
    image.height = 32U;
    image.stride_pixels = image.width;
    image.pixels.assign(
        static_cast<std::size_t>(image.width) * image.height,
        negaflow::core::Rgba32F{0.005F, 0.005F, 0.005F, 1.0F});
    for (std::uint32_t row = 12U; row < 16U; ++row) {
        for (std::uint32_t column = 12U; column < 18U; ++column) {
            image.pixels[static_cast<std::size_t>(row) * image.width + column] = {
                0.949992359F,
                0.85F,
                0.7500076F,
                1.0F,
            };
        }
    }
    return image;
}

negaflow::imaging::WorkingImage make_auto_base_edge_fraction_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 100U;
    image.height = 50U;
    image.stride_pixels = image.width;
    image.pixels.assign(
        static_cast<std::size_t>(image.width) * image.height,
        negaflow::core::Rgba32F{0.005F, 0.005F, 0.005F, 1.0F});
    for (const std::uint32_t first_column : {0U, 15U, 30U, 45U, 60U}) {
        for (std::uint32_t column = first_column; column < first_column + 13U; ++column) {
            image.pixels[2U * image.width + column] = {0.70F, 0.50F, 0.30F, 1.0F};
        }
    }
    return image;
}

negaflow::imaging::WorkingImage make_scene_edge_fallback_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 128U;
    image.height = 64U;
    image.stride_pixels = image.width;
    image.pixels.assign(
        static_cast<std::size_t>(image.width) * image.height,
        negaflow::core::Rgba32F{0.005F, 0.005F, 0.005F, 1.0F});
    for (std::uint32_t index = 0U; index < 20U; ++index) {
        const std::uint32_t column = 4U + index * 6U;
        image.pixels[column] = {0.48F, 0.32F, 0.16F, 1.0F};
        image.pixels[
            static_cast<std::size_t>(image.height - 1U) * image.width + column] =
            {0.48F, 0.32F, 0.16F, 1.0F};
    }
    return image;
}

negaflow::imaging::WorkingImage make_affine_scene_edge_fallback_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 640U;
    image.height = 64U;
    image.stride_pixels = image.width;
    image.pixels.assign(
        static_cast<std::size_t>(image.width) * image.height,
        negaflow::core::Rgba32F{0.005F, 0.005F, 0.005F, 1.0F});
    for (std::uint32_t index = 0U; index < 20U; ++index) {
        const std::uint32_t target_column = 4U + index * 15U;
        const std::uint32_t source_column = target_column * 2U;
        for (const std::uint32_t row : {0U, 1U, image.height - 2U, image.height - 1U}) {
            image.pixels[static_cast<std::size_t>(row) * image.width + source_column] =
                {0.005F, 0.005F, 0.005F, 1.0F};
            image.pixels[static_cast<std::size_t>(row) * image.width + source_column + 1U] =
                {0.955F, 0.635F, 0.315F, 1.0F};
        }
    }
    return image;
}

negaflow::imaging::WorkingImage make_uniform_working_image(
    const negaflow::core::Rgba32F pixel,
    const std::uint32_t width = 64U,
    const std::uint32_t height = 16U) {
    negaflow::imaging::WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.assign(static_cast<std::size_t>(width) * height, pixel);
    return image;
}

void test_muted_scene_vibrance() {
    auto muted = make_uniform_working_image({0.52F, 0.50F, 0.48F, 0.75F});
    const auto muted_original = muted.pixels.front();
    const auto muted_result = negaflow::imaging::apply_muted_scene_vibrance(
        {muted.pixels.data(), muted.pixels.size(), muted.width, muted.height,
         muted.stride_pixels},
        false);
    const double expected_mean = (0.52 - 0.48) / 0.52;
    const double expected_amount = (0.24 - expected_mean) * 3.0;
    expect(
        muted_result.status == negaflow::core::KernelStatus::ok &&
            muted_result.info.applied &&
            std::abs(muted_result.info.mean_saturation - expected_mean) < 1.0e-6 &&
            std::abs(muted_result.info.amount - expected_amount) < 1.0e-6 &&
            (muted.pixels.front().red - muted.pixels.front().blue) >
                (muted_original.red - muted_original.blue) &&
            muted.pixels.front().alpha == muted_original.alpha,
        "muted color scene receives the measured low-chroma boost");

    auto saturated = make_uniform_working_image({0.80F, 0.30F, 0.10F, 1.0F});
    const auto saturated_original = saturated.pixels;
    const auto saturated_result = negaflow::imaging::apply_muted_scene_vibrance(
        {saturated.pixels.data(), saturated.pixels.size(), saturated.width,
         saturated.height, saturated.stride_pixels},
        false);
    expect(
        saturated_result.status == negaflow::core::KernelStatus::ok &&
            !saturated_result.info.applied && saturated_result.info.amount == 0.0 &&
            images_equal(saturated.pixels, saturated_original),
        "already saturated color scene is an exact identity");

    auto monochrome = make_uniform_working_image({0.52F, 0.50F, 0.48F, 1.0F});
    const auto monochrome_original = monochrome.pixels;
    const auto monochrome_result = negaflow::imaging::apply_muted_scene_vibrance(
        {monochrome.pixels.data(), monochrome.pixels.size(), monochrome.width,
         monochrome.height, monochrome.stride_pixels},
        true);
    expect(
        monochrome_result.status == negaflow::core::KernelStatus::ok &&
            !monochrome_result.info.applied &&
            images_equal(monochrome.pixels, monochrome_original),
        "B&W scene bypasses muted-scene vibrance");

    auto tiny = make_uniform_working_image({0.52F, 0.50F, 0.48F, 1.0F}, 4U, 4U);
    const auto tiny_original = tiny.pixels;
    const auto tiny_result = negaflow::imaging::apply_muted_scene_vibrance(
        {tiny.pixels.data(), tiny.pixels.size(), tiny.width, tiny.height,
         tiny.stride_pixels},
        false);
    expect(
        tiny_result.status == negaflow::core::KernelStatus::ok &&
            tiny_result.info.mean_saturation == 0.5 &&
            !tiny_result.info.applied && images_equal(tiny.pixels, tiny_original),
        "tiny scene follows the macOS measurement fallback identity");
}

}  // namespace

int main() {
    test_muted_scene_vibrance();
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
    expect(
        scene.info.muted_scene_vibrance.applied &&
            scene.info.muted_scene_vibrance.amount == 0.5,
        "non-preset color scene runs muted-scene vibrance after inversion");

    const auto affine_proxy_scene = negaflow::imaging::develop_manual_negative(
        make_affine_proxy_scene_image(),
        {{0.80F, 0.80F, 0.80F}, negaflow::imaging::NegativeFilmType::color});
    const float affine_proxy_expected = std::log10(0.80F / 0.12F);
    expect(
        affine_proxy_scene.status == negaflow::imaging::ManualNegativeDevelopStatus::ok &&
            std::abs(affine_proxy_scene.info.dmax_normalized[0] - affine_proxy_expected) < 1.0e-5F &&
            std::abs(affine_proxy_scene.info.dmax_normalized[1] - affine_proxy_expected) < 1.0e-5F &&
            std::abs(affine_proxy_scene.info.dmax_normalized[2] - affine_proxy_expected) < 1.0e-5F,
        "scene-range proxy uses uniform pixel-centre bilinear affine sampling on both axes");

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
    expect(
        !preset_scene.info.muted_scene_vibrance.applied,
        "preset color scene bypasses muted-scene vibrance");

    const auto scene_bw = negaflow::imaging::develop_manual_negative(
        make_scene_working_image(),
        {scene_parameters.dmin, negaflow::imaging::NegativeFilmType::black_and_white});
    expect(
        scene_bw.status == negaflow::imaging::ManualNegativeDevelopStatus::ok &&
            scene_bw.info.dmax_normalized[0] == scene_bw.info.dmax_normalized[1] &&
            scene_bw.info.dmax_normalized[1] == scene_bw.info.dmax_normalized[2],
        "B&W scene range remains neutral");
    expect(
        !scene_bw.info.muted_scene_vibrance.applied,
        "B&W scene-ranged development bypasses muted-scene vibrance");

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
