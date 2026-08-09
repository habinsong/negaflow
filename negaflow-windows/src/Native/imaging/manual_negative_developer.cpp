#include "negaflow/imaging/manual_negative_developer.h"

#include "negaflow/core/negative_inversion.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <optional>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
}

[[nodiscard]] bool has_compatible_layout(const WorkingImage& image) noexcept {
    if (image.width <= 8U || image.height <= 8U || image.stride_pixels < image.width) {
        return false;
    }
    const std::size_t required =
        static_cast<std::size_t>(image.stride_pixels) * image.height;
    return required / image.height == image.stride_pixels && image.pixels.size() >= required;
}

[[nodiscard]] float percentile(
    const std::vector<float>& sorted,
    const double fraction) noexcept {
    const std::size_t index = std::min(
        sorted.size() - 1U,
        static_cast<std::size_t>(static_cast<double>(sorted.size() - 1U) * fraction));
    return sorted[index];
}

[[nodiscard]] std::optional<std::array<float, 3>> scene_density_range(
    const WorkingImage& image,
    const std::array<float, 3>& dmin,
    const negaflow::core::PrintResponse& response,
    const NegativeFilmType film_type) noexcept {
    if (!has_compatible_layout(image)) {
        return std::nullopt;
    }

    // This mirrors the macOS sampleStats geometry: a 64...320-wide linear sample and
    // a 6% frame inset. The bounded sample count keeps a panoramic source from turning a
    // statistic into a second full-frame allocation.
    constexpr std::uint32_t maximum_sample_width = 320U;
    constexpr std::uint32_t minimum_sample_width = 64U;
    // A normal 2:3 portrait frame produces the macOS 320 x 480 sample grid. Keep that
    // grid intact; only more extreme panoramas are reduced before allocating statistics.
    constexpr std::size_t maximum_sample_count = 153600U;
    std::uint64_t sample_width = std::clamp(
        image.width,
        minimum_sample_width,
        maximum_sample_width);
    std::uint64_t sample_height = std::max<std::uint64_t>(
        1U,
        (static_cast<std::uint64_t>(image.height) * sample_width) / image.width);
    const std::uint64_t sample_count = sample_width * sample_height;
    if (sample_count > maximum_sample_count) {
        const double scale = std::sqrt(
            static_cast<double>(maximum_sample_count) / static_cast<double>(sample_count));
        sample_width = std::max<std::uint64_t>(
            1U,
            static_cast<std::uint64_t>(sample_width * scale));
        sample_height = std::max<std::uint64_t>(
            1U,
            static_cast<std::uint64_t>(sample_height * scale));
    }

    const std::uint32_t bounded_width = static_cast<std::uint32_t>(sample_width);
    const std::uint32_t bounded_height = static_cast<std::uint32_t>(sample_height);

    const std::uint32_t inset_x = std::max(1U, static_cast<std::uint32_t>(bounded_width * 0.06));
    const std::uint32_t inset_y = std::max(1U, static_cast<std::uint32_t>(bounded_height * 0.06));
    if (bounded_width <= inset_x * 2U || bounded_height <= inset_y * 2U) {
        return std::nullopt;
    }

    try {
        std::vector<negaflow::core::Rgba32F> pixels;
        pixels.reserve(static_cast<std::size_t>(bounded_width - (inset_x * 2U)) *
                       (bounded_height - (inset_y * 2U)));
        for (std::uint32_t y = inset_y; y < bounded_height - inset_y; ++y) {
            const std::uint32_t source_y = std::min(
                image.height - 1U,
                static_cast<std::uint32_t>((static_cast<std::uint64_t>(y) * image.height) / bounded_height));
            const std::size_t row_offset = static_cast<std::size_t>(source_y) * image.stride_pixels;
            for (std::uint32_t x = inset_x; x < bounded_width - inset_x; ++x) {
                const std::uint32_t source_x = std::min(
                    image.width - 1U,
                    static_cast<std::uint32_t>((static_cast<std::uint64_t>(x) * image.width) / bounded_width));
                const negaflow::core::Rgba32F pixel = image.pixels[row_offset + source_x];
                if (!std::isfinite(pixel.red) || !std::isfinite(pixel.green) ||
                    !std::isfinite(pixel.blue)) {
                    return std::nullopt;
                }
                pixels.push_back(pixel);
            }
        }
        if (pixels.size() < 64U) {
            return std::nullopt;
        }

        const float base_luma = (dmin[0] + dmin[1] + dmin[2]) / 3.0F;
        const float gate = base_luma * 1.12F;
        const float dark_cut = base_luma * 0.15F;
        const float base_ratio = dmin[0] / std::max(dmin[2], 1.0e-4F);
        const std::optional<float> neutral_dark_ratio_cut = base_ratio >= 1.5F
            ? std::optional<float>{base_ratio * 0.55F}
            : std::nullopt;
        std::vector<negaflow::core::Rgba32F> film;
        film.reserve(pixels.size());
        for (const negaflow::core::Rgba32F pixel : pixels) {
            const float luma = (pixel.red + pixel.green + pixel.blue) / 3.0F;
            if (luma > gate ||
                (neutral_dark_ratio_cut && luma < dark_cut &&
                 pixel.red / std::max(pixel.blue, 1.0e-4F) < *neutral_dark_ratio_cut)) {
                continue;
            }
            film.push_back(pixel);
        }
        if (film.size() < 64U) {
            film = std::move(pixels);
        }

        std::array<std::vector<float>, 3> channels{};
        for (auto& channel : channels) {
            channel.reserve(film.size());
        }
        for (const negaflow::core::Rgba32F pixel : film) {
            channels[0].push_back(pixel.red);
            channels[1].push_back(pixel.green);
            channels[2].push_back(pixel.blue);
        }
        for (auto& channel : channels) {
            std::sort(channel.begin(), channel.end());
        }

        std::array<float, 3> measured{};
        for (std::size_t channel = 0U; channel < measured.size(); ++channel) {
            const float densest = std::max(percentile(channels[channel], 0.002), 1.0e-5F);
            const float densest_floor = std::max(
                densest,
                dmin[channel] * std::pow(10.0F, -1.8F));
            measured[channel] = std::max(0.4F, std::log10(dmin[channel] / densest_floor));
        }
        const float geometric_mean = std::pow(
            measured[0] * measured[1] * measured[2],
            1.0F / 3.0F);
        const float transition = std::clamp((geometric_mean - 0.42F) / 0.20F, 0.0F, 1.0F);
        const float confidence = transition * transition * (3.0F - (2.0F * transition));
        const float scale = response.normal_range +
            ((geometric_mean - response.normal_range) * confidence);
        if (film_type == NegativeFilmType::black_and_white) {
            return std::array<float, 3>{scale, scale, scale};
        }
        std::array<float, 3> result{};
        for (std::size_t channel = 0U; channel < result.size(); ++channel) {
            result[channel] = scale *
                (1.0F + ((measured[channel] / geometric_mean) - 1.0F) * confidence);
        }
        return result;
    } catch (const std::bad_alloc&) {
        return std::nullopt;
    }
}

}  // namespace

ManualNegativeDevelopResult develop_manual_negative(
    WorkingImage image,
    const ManualNegativeDevelopParameters& parameters) noexcept {
    ManualNegativeDevelopResult result{};
    result.image = std::move(image);

    negaflow::core::PrintResponse response{};
    switch (parameters.film_type) {
        case NegativeFilmType::color:
            response = negaflow::core::color_negative_print_response();
            break;
        case NegativeFilmType::black_and_white:
            response = negaflow::core::black_and_white_negative_print_response();
            break;
        default:
            discard_pixels(result.image);
            return result;
    }

    for (std::size_t channel = 0U; channel < parameters.dmin.size(); ++channel) {
        if (!std::isfinite(parameters.dmin[channel])) {
            discard_pixels(result.image);
            return result;
        }
        result.info.applied_dmin[channel] =
            std::clamp(parameters.dmin[channel], minimum_manual_dmin, maximum_manual_dmin);
        result.info.dmax_normalized[channel] = response.normal_range;
    }
    const auto adaptive = scene_density_range(
        result.image,
        result.info.applied_dmin,
        response,
        parameters.film_type);
    if (!parameters.use_preset_response) {
        if (adaptive) {
            result.info.dmax_normalized = *adaptive;
        }
    } else {
        for (const float dmax : parameters.preset_dmax_normalized) {
            if (!std::isfinite(dmax) || dmax <= 0.0F) {
                discard_pixels(result.image);
                return result;
            }
        }
        const float scene_scale = adaptive
            ? std::pow((*adaptive)[0] * (*adaptive)[1] * (*adaptive)[2], 1.0F / 3.0F)
            : response.normal_range;
        if (parameters.film_type == NegativeFilmType::black_and_white) {
            result.info.dmax_normalized = {scene_scale, scene_scale, scene_scale};
        } else {
            const float preset_scale = std::pow(
                parameters.preset_dmax_normalized[0] *
                    parameters.preset_dmax_normalized[1] *
                    parameters.preset_dmax_normalized[2],
                1.0F / 3.0F);
            for (std::size_t channel = 0U; channel < 3U; ++channel) {
                result.info.dmax_normalized[channel] = scene_scale *
                    parameters.preset_dmax_normalized[channel] / preset_scale;
            }
        }
    }

    const negaflow::core::NegativeInversionParameters kernel_parameters{
        result.info.applied_dmin,
        result.info.dmax_normalized,
    };
    const negaflow::core::ConstImageView input{
        result.image.pixels.data(),
        result.image.pixels.size(),
        result.image.width,
        result.image.height,
        result.image.stride_pixels,
    };
    const negaflow::core::ImageView output{
        result.image.pixels.data(),
        result.image.pixels.size(),
        result.image.width,
        result.image.height,
        result.image.stride_pixels,
    };
    result.info.kernel_status = negaflow::core::apply_negative_inversion(
        input,
        output,
        kernel_parameters,
        response);
    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = ManualNegativeDevelopStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }

    result.status = ManualNegativeDevelopStatus::ok;
    return result;
}

const char* manual_negative_develop_status_name(
    const ManualNegativeDevelopStatus status) noexcept {
    switch (status) {
        case ManualNegativeDevelopStatus::ok:
            return "ok";
        case ManualNegativeDevelopStatus::invalid_parameter:
            return "invalid_parameter";
        case ManualNegativeDevelopStatus::kernel_failed:
            return "kernel_failed";
    }
    return "unknown";
}

const char* negative_film_type_name(const NegativeFilmType film_type) noexcept {
    switch (film_type) {
        case NegativeFilmType::color:
            return "color";
        case NegativeFilmType::black_and_white:
            return "bw";
    }
    return "unknown";
}

}  // namespace negaflow::imaging
