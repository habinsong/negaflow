#include "negaflow/imaging/scene_correction.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <limits>
#include <new>
#include <vector>

namespace negaflow::imaging {
namespace {

constexpr double minimum_range = 0.04;
constexpr double negative_output_black = 0.003;
constexpr double negative_output_white = 0.95;
constexpr double positive_output_black = 0.014;
constexpr double positive_output_white = 0.86;

struct ChannelSamples final {
    std::vector<double> red{};
    std::vector<double> green{};
    std::vector<double> blue{};
};

[[nodiscard]] double overlap(
    const double a0,
    const double a1,
    const double b0,
    const double b1) noexcept {
    return std::max(0.0, std::min(a1, b1) - std::max(a0, b0));
}

[[nodiscard]] bool collect_area_samples(
    const negaflow::core::ImageView image,
    const std::uint32_t target_width,
    ChannelSamples& samples) {
    if (image.width <= 4U || image.height <= 4U) {
        return false;
    }
    const double scale = static_cast<double>(target_width) /
                         static_cast<double>(image.width);
    const double scaled_height =
        std::floor(static_cast<double>(image.height) * scale);
    if (!std::isfinite(scaled_height) || scaled_height < 1.0 ||
        scaled_height > 65536.0) {
        return false;
    }
    const std::uint32_t target_height =
        static_cast<std::uint32_t>(scaled_height);
    const std::uint64_t count64 =
        static_cast<std::uint64_t>(target_width) * target_height;
    if (count64 < 64U || count64 > 16U * 1024U * 1024U ||
        count64 > std::numeric_limits<std::size_t>::max()) {
        return false;
    }
    const std::size_t count = static_cast<std::size_t>(count64);
    samples.red.reserve(count);
    samples.green.reserve(count);
    samples.blue.reserve(count);

    const double inverse_scale = 1.0 / scale;
    for (std::uint32_t target_y = 0U; target_y < target_height; ++target_y) {
        const double top = static_cast<double>(target_y) * inverse_scale;
        const double bottom = static_cast<double>(target_y + 1U) * inverse_scale;
        const std::uint32_t first_y = static_cast<std::uint32_t>(std::floor(top));
        const std::uint32_t last_y = std::min(
            image.height,
            static_cast<std::uint32_t>(std::ceil(bottom)));
        for (std::uint32_t target_x = 0U; target_x < target_width; ++target_x) {
            const double left = static_cast<double>(target_x) * inverse_scale;
            const double right = static_cast<double>(target_x + 1U) * inverse_scale;
            const std::uint32_t first_x =
                static_cast<std::uint32_t>(std::floor(left));
            const std::uint32_t last_x = std::min(
                image.width,
                static_cast<std::uint32_t>(std::ceil(right)));
            std::array<double, 3> sum{};
            double weight_sum = 0.0;
            for (std::uint32_t y = first_y; y < last_y; ++y) {
                const double y_weight = overlap(
                    top, bottom, static_cast<double>(y), static_cast<double>(y + 1U));
                const std::size_t row = static_cast<std::size_t>(y) * image.stride_pixels;
                for (std::uint32_t x = first_x; x < last_x; ++x) {
                    const double weight = y_weight * overlap(
                        left, right, static_cast<double>(x), static_cast<double>(x + 1U));
                    const negaflow::core::Rgba32F pixel = image.pixels[row + x];
                    sum[0] += static_cast<double>(pixel.red) * weight;
                    sum[1] += static_cast<double>(pixel.green) * weight;
                    sum[2] += static_cast<double>(pixel.blue) * weight;
                    weight_sum += weight;
                }
            }
            if (weight_sum <= 0.0) {
                return false;
            }
            samples.red.push_back(sum[0] / weight_sum);
            samples.green.push_back(sum[1] / weight_sum);
            samples.blue.push_back(sum[2] / weight_sum);
        }
    }
    std::sort(samples.red.begin(), samples.red.end());
    std::sort(samples.green.begin(), samples.green.end());
    std::sort(samples.blue.begin(), samples.blue.end());
    return true;
}

[[nodiscard]] double percentile(
    const std::vector<double>& values,
    const double fraction) noexcept {
    const std::size_t index = std::min(
        values.size() - 1U,
        static_cast<std::size_t>(static_cast<double>(values.size()) * fraction));
    return values[index];
}

[[nodiscard]] bool apply_auto_levels(
    const negaflow::core::ImageView image,
    const bool negative_source,
    SceneCorrectionInfo& info) {
    ChannelSamples samples{};
    if (!collect_area_samples(image, 256U, samples)) {
        return false;
    }
    info.sampled_pixels += samples.red.size();
    const double black_clip = negative_source ? 0.005 : 0.002;
    const std::array<double, 3> black{
        percentile(samples.red, black_clip),
        percentile(samples.green, black_clip),
        percentile(samples.blue, black_clip),
    };
    const std::array<double, 3> white{
        percentile(samples.red, 0.999),
        percentile(samples.green, 0.999),
        percentile(samples.blue, 0.999),
    };
    const double maximum_range = std::max({
        white[0] - black[0], white[1] - black[1], white[2] - black[2]});
    if (maximum_range < minimum_range ||
        (white[0] > 0.95 && white[1] > 0.95 && white[2] > 0.95 &&
         black[0] < 0.05 && black[1] < 0.05 && black[2] < 0.05)) {
        return false;
    }

    const double output_black = negative_source
        ? negative_output_black
        : positive_output_black;
    const double output_white = negative_source
        ? negative_output_white
        : positive_output_white;
    std::array<double, 3> scale{1.0, 1.0, 1.0};
    std::array<double, 3> bias{};
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        const double range = white[channel] - black[channel];
        if (range >= minimum_range) {
            scale[channel] = (output_white - output_black) / range;
            bias[channel] = output_black - (black[channel] * scale[channel]);
        }
    }
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        const std::size_t row = static_cast<std::size_t>(y) * image.stride_pixels;
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            negaflow::core::Rgba32F& pixel = image.pixels[row + x];
            pixel.red = static_cast<float>(std::clamp(
                (static_cast<double>(pixel.red) * scale[0]) + bias[0], 0.0, 1.0));
            pixel.green = static_cast<float>(std::clamp(
                (static_cast<double>(pixel.green) * scale[1]) + bias[1], 0.0, 1.0));
            pixel.blue = static_cast<float>(std::clamp(
                (static_cast<double>(pixel.blue) * scale[2]) + bias[2], 0.0, 1.0));
        }
    }
    return true;
}

[[nodiscard]] float cube_curve(const float value, const double gamma) noexcept {
    constexpr std::size_t dimension = 32U;
    const double position = static_cast<double>(std::clamp(value, 0.0F, 1.0F)) *
                            static_cast<double>(dimension - 1U);
    const std::size_t lower = static_cast<std::size_t>(position);
    const std::size_t upper = std::min(dimension - 1U, lower + 1U);
    const double t = position - static_cast<double>(lower);
    const double a = std::pow(
        static_cast<double>(lower) / static_cast<double>(dimension - 1U), gamma);
    const double b = std::pow(
        static_cast<double>(upper) / static_cast<double>(dimension - 1U), gamma);
    return static_cast<float>(a + ((b - a) * t));
}

[[nodiscard]] bool apply_neutral_balance(
    const negaflow::core::ImageView image,
    SceneCorrectionInfo& info) {
    if (image.width <= 8U || image.height <= 8U) {
        return false;
    }
    ChannelSamples samples{};
    if (!collect_area_samples(image, 192U, samples)) {
        return false;
    }
    info.sampled_pixels += samples.red.size();
    const std::size_t middle = samples.red.size() / 2U;
    const std::array<double, 3> median{
        samples.red[middle], samples.green[middle], samples.blue[middle]};
    for (const double value : median) {
        if (value <= 0.04 || value >= 0.96) {
            return false;
        }
    }
    const double target = std::pow(median[0] * median[1] * median[2], 1.0 / 3.0);
    std::array<double, 3> gamma{};
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        const double raw = std::log(target) / std::log(median[channel]);
        gamma[channel] = std::clamp(1.0 + ((raw - 1.0) * 0.8), 0.80, 1.25);
    }
    if (std::abs(gamma[0] - 1.0) <= 0.01 &&
        std::abs(gamma[1] - 1.0) <= 0.01 &&
        std::abs(gamma[2] - 1.0) <= 0.01) {
        return false;
    }
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        const std::size_t row = static_cast<std::size_t>(y) * image.stride_pixels;
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            negaflow::core::Rgba32F& pixel = image.pixels[row + x];
            pixel.red = cube_curve(pixel.red, gamma[0]);
            pixel.green = cube_curve(pixel.green, gamma[1]);
            pixel.blue = cube_curve(pixel.blue, gamma[2]);
        }
    }
    return true;
}

}  // namespace

negaflow::core::KernelStatus apply_scene_correction(
    const negaflow::core::ImageView image,
    const SceneCorrectionParameters& parameters,
    SceneCorrectionInfo& info) noexcept {
    info = {};
    const negaflow::core::KernelStatus view_status =
        negaflow::core::validate_image_view(image);
    if (view_status != negaflow::core::KernelStatus::ok) {
        return view_status;
    }
    const negaflow::core::KernelStatus input_status =
        negaflow::core::validate_finite_pixels({
            image.pixels, image.pixel_capacity, image.width, image.height,
            image.stride_pixels});
    if (input_status != negaflow::core::KernelStatus::ok) {
        return input_status;
    }
    try {
        if (parameters.auto_levels) {
            info.auto_levels_applied =
                apply_auto_levels(image, parameters.negative_source, info);
        }
        if (parameters.auto_neutral_balance && parameters.negative_source) {
            info.neutral_balance_applied = apply_neutral_balance(image, info);
        }
    } catch (const std::bad_alloc&) {
        return negaflow::core::KernelStatus::buffer_too_small;
    } catch (...) {
        return negaflow::core::KernelStatus::invalid_argument;
    }
    return negaflow::core::validate_finite_pixels({
        image.pixels, image.pixel_capacity, image.width, image.height,
        image.stride_pixels});
}

}  // namespace negaflow::imaging
