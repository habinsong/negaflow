#include "negaflow/imaging/muted_scene_vibrance.h"

#include "bilinear_rgb_sampler.h"
#include "vibrance_math.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace negaflow::imaging {
namespace {

constexpr std::uint32_t minimum_proxy_width = 32U;
constexpr std::uint32_t maximum_proxy_width = 160U;
constexpr double saturation_target = 0.24;
constexpr double maximum_vibrance = 0.5;
constexpr double vibrance_scale = 3.0;
constexpr double activation_threshold = 0.01;

[[nodiscard]] double scene_mean_saturation(
    const negaflow::core::ImageView image) noexcept {
    if (image.width <= 4U || image.height <= 4U) {
        return 0.5;
    }

    const std::uint32_t target_width = std::max(
        minimum_proxy_width,
        std::min(maximum_proxy_width, image.width));
    const double scale =
        static_cast<double>(target_width) / static_cast<double>(image.width);
    const std::uint64_t target_height = std::max<std::uint64_t>(
        1U,
        static_cast<std::uint64_t>(static_cast<double>(image.height) * scale));
    const negaflow::core::ConstImageView source{
        image.pixels,
        image.pixel_capacity,
        image.width,
        image.height,
        image.stride_pixels,
    };

    double sum = 0.0;
    for (std::uint64_t row = 0U; row < target_height; ++row) {
        const double source_y =
            (static_cast<double>(row) + 0.5) / scale - 0.5;
        for (std::uint32_t column = 0U; column < target_width; ++column) {
            const double source_x =
                (static_cast<double>(column) + 0.5) / scale - 0.5;
            const detail::BilinearRgb pixel =
                detail::sample_bilinear_rgb_transparent(source, source_x, source_y);
            const double maximum =
                std::max(pixel.red, std::max(pixel.green, pixel.blue));
            const double minimum =
                std::min(pixel.red, std::min(pixel.green, pixel.blue));
            sum += maximum > 1.0e-6 ? (maximum - minimum) / maximum : 0.0;
        }
    }
    const double sample_count =
        static_cast<double>(target_width) * static_cast<double>(target_height);
    return sum / std::max(sample_count, 1.0);
}

}  // namespace

MutedSceneVibranceResult apply_muted_scene_vibrance(
    const negaflow::core::ImageView image,
    const bool monochrome) noexcept {
    MutedSceneVibranceResult result{};
    if (monochrome) {
        result.status = negaflow::core::KernelStatus::ok;
        return result;
    }

    const negaflow::core::ConstImageView input{
        image.pixels,
        image.pixel_capacity,
        image.width,
        image.height,
        image.stride_pixels,
    };
    result.status = negaflow::core::validate_finite_pixels(input);
    if (result.status != negaflow::core::KernelStatus::ok) {
        return result;
    }

    result.info.mean_saturation = scene_mean_saturation(image);
    result.info.amount = std::clamp(
        (saturation_target - result.info.mean_saturation) * vibrance_scale,
        0.0,
        maximum_vibrance);
    if (result.info.amount <= activation_threshold) {
        result.status = negaflow::core::KernelStatus::ok;
        return result;
    }

    const float amount = static_cast<float>(result.info.amount);
    for (std::uint32_t row = 0U; row < image.height; ++row) {
        auto* const row_pixels =
            image.pixels + (static_cast<std::size_t>(row) * image.stride_pixels);
        for (std::uint32_t column = 0U; column < image.width; ++column) {
            auto& pixel = row_pixels[column];
            detail::apply_vibrance_to_channels(
                pixel.red,
                pixel.green,
                pixel.blue,
                amount);
            if (!std::isfinite(pixel.red) || !std::isfinite(pixel.green) ||
                !std::isfinite(pixel.blue)) {
                result.status = negaflow::core::KernelStatus::non_finite_output;
                return result;
            }
        }
    }
    result.info.applied = true;
    result.status = negaflow::core::KernelStatus::ok;
    return result;
}

}  // namespace negaflow::imaging
