#include "negaflow/imaging/scanner_target_grade.h"

#include "scanner_target_color.h"
#include "scanner_target_measure.h"
#include "scanner_target_profile.h"
#include "scanner_target_response.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <new>
#include <string_view>
#include <vector>

namespace negaflow::imaging {
namespace {

using namespace negaflow::imaging::scanner_target_detail;

void apply_profile_grade(
    const negaflow::core::ImageView image,
    const TargetProfile& profile,
    const double strength,
    const double anchor_weight,
    const double scene_median,
    const bool monochrome) noexcept {
    const double chroma_keep = 1.0 - std::min(anchor_weight, 0.65);
    std::array<double, 9U> tone{};
    for (std::size_t i = 0U; i < tone.size(); ++i) {
        tone[i] = clamp(
            profile.tone_xs[i] + (profile.tone_delta[i] * strength),
            0.002,
            0.998);
    }
    const double clamped_median = clamp(
        scene_median, profile.tone_xs.front(), profile.tone_xs.back());
    const double mapped_median = relative_tone(
        clamped_median, profile.tone_xs, tone);
    const double offset = std::round(
        ((mapped_median - clamped_median) * anchor_weight) / 0.004) * 0.004;
    if (std::abs(offset) > 1.0e-9) {
        for (std::size_t i = 0U; i < tone.size(); ++i) {
            tone[i] = clamp(
                tone[i] - (offset * smoothstep(0.05, 0.25, profile.tone_xs[i])),
                0.002,
                0.998);
        }
    }

    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            auto& pixel = image.pixels[
                static_cast<std::size_t>(y) * image.stride_pixels + x];
            const Rgb encoded{
                srgb_encode(pixel.red),
                srgb_encode(pixel.green),
                srgb_encode(pixel.blue),
            };
            const double low = std::min({encoded.red, encoded.green, encoded.blue});
            const double high = std::max({encoded.red, encoded.green, encoded.blue});
            const double domain_weight = smoothstep(0.0, 0.02, low) *
                (1.0 - smoothstep(0.98, 1.0, high));
            if (domain_weight <= 0.0) continue;
            const Rgb candidate = transformed_srgb(
                encoded, profile, tone, strength, chroma_keep, monochrome, false);
            const Rgb reciprocal = transformed_srgb(
                encoded, profile, tone, strength, chroma_keep, monochrome, true);
            const double scale = gamut_scale(encoded, candidate, reciprocal);
            const Rgb graded{
                srgb_decode(encoded.red + ((candidate.red - encoded.red) * scale)),
                srgb_decode(encoded.green + ((candidate.green - encoded.green) * scale)),
                srgb_decode(encoded.blue + ((candidate.blue - encoded.blue) * scale)),
            };
            pixel.red = static_cast<float>(
                pixel.red + ((graded.red - pixel.red) * domain_weight));
            pixel.green = static_cast<float>(
                pixel.green + ((graded.green - pixel.green) * domain_weight));
            pixel.blue = static_cast<float>(
                pixel.blue + ((graded.blue - pixel.blue) * domain_weight));
        }
    }
}

void apply_noritsu_texture(
    const negaflow::core::ImageView image,
    std::vector<Rgb>& scratch) {
    constexpr std::array<double, 5U> weights{{0.037657, 0.239936, 0.444814, 0.239936, 0.037657}};
    const auto coordinate = [](const std::int64_t value, const std::uint32_t limit) {
        return static_cast<std::uint32_t>(std::clamp<std::int64_t>(value, 0, limit - 1U));
    };
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            Rgb sum{};
            for (std::int64_t k = -2; k <= 2; ++k) {
                const auto sample = image.pixels[static_cast<std::size_t>(y) * image.stride_pixels +
                    coordinate(static_cast<std::int64_t>(x) + k, image.width)];
                const double w = weights[static_cast<std::size_t>(k + 2)];
                sum.red += sample.red * w; sum.green += sample.green * w; sum.blue += sample.blue * w;
            }
            scratch[static_cast<std::size_t>(y) * image.width + x] = sum;
        }
    }
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            Rgb blur{};
            for (std::int64_t k = -2; k <= 2; ++k) {
                const Rgb sample = scratch[static_cast<std::size_t>(coordinate(
                    static_cast<std::int64_t>(y) + k, image.height)) * image.width + x];
                const double w = weights[static_cast<std::size_t>(k + 2)];
                blur.red += sample.red * w; blur.green += sample.green * w; blur.blue += sample.blue * w;
            }
            auto& pixel = image.pixels[static_cast<std::size_t>(y) * image.stride_pixels + x];
            const double low = std::min({pixel.red, pixel.green, pixel.blue});
            const double high = std::max({pixel.red, pixel.green, pixel.blue});
            const double original_luma = (0.2126 * pixel.red) + (0.7152 * pixel.green) + (0.0722 * pixel.blue);
            if (low < 0.0 || high > 1.0 || original_luma <= 1.0e-5) continue;
            const double blur_luma = clamp((0.2126 * blur.red) + (0.7152 * blur.green) +
                (0.0722 * blur.blue), 0.0, 1.0);
            const double y_original = srgb_encode(original_luma);
            const double y_blur = srgb_encode(blur_luma);
            const double floor_y = std::max(y_original * 0.45, std::min(y_original, 0.008));
            const double y_new = clamp(y_original + (0.6 * (y_original - y_blur)), floor_y, 1.0);
            double gain = srgb_decode(y_new) / original_luma;
            const double maximum = high * gain;
            if (maximum > 1.0) gain /= maximum;
            pixel.red = static_cast<float>(pixel.red * gain);
            pixel.green = static_cast<float>(pixel.green * gain);
            pixel.blue = static_cast<float>(pixel.blue * gain);
        }
    }
}

}  // namespace

negaflow::core::KernelStatus apply_scanner_target_grade(
    const negaflow::core::ImageView image,
    const ScannerTargetStyle target,
    const bool monochrome,
    const bool positive,
    const std::wstring_view scanner_profile_id,
    ScannerTargetGradeInfo& info) noexcept {
    info = {};
    const auto input = negaflow::core::ConstImageView{
        image.pixels, image.pixel_capacity, image.width, image.height, image.stride_pixels};
    const auto view_status = negaflow::core::validate_image_view(image);
    if (view_status != negaflow::core::KernelStatus::ok) return view_status;
    const auto finite_status = negaflow::core::validate_finite_pixels(input);
    if (finite_status != negaflow::core::KernelStatus::ok) return finite_status;

    try {
        const TargetProfile& profile = profile_for(target);
        const double strength = positive ? 0.5 : 1.0;
        double scene_median = 0.5;
        const double anchor_weight = scene_anchor_weight(image, scene_median);
        info.scene_anchor_weight = static_cast<float>(anchor_weight);

        if (monochrome) {
            for (std::uint32_t y = 0U; y < image.height; ++y) {
                for (std::uint32_t x = 0U; x < image.width; ++x) {
                    auto& pixel = image.pixels[static_cast<std::size_t>(y) * image.stride_pixels + x];
                    const float gray = (0.2126F * pixel.red) + (0.7152F * pixel.green) +
                        (0.0722F * pixel.blue);
                    pixel.red = gray; pixel.green = gray; pixel.blue = gray;
                }
            }
        }

        apply_profile_grade(
            image, profile, strength, anchor_weight, scene_median, monochrome);
        if (!positive) {
            if (const TargetProfile* const relative =
                    relative_profile_for(target, scanner_profile_id)) {
                apply_profile_grade(
                    image, *relative, 1.0, anchor_weight, scene_median, monochrome);
                info.relative_signature_applied = true;
            }
        }

        if (target == ScannerTargetStyle::noritsu) {
            std::vector<Rgb> scratch(
                static_cast<std::size_t>(image.width) * image.height);
            apply_noritsu_texture(image, scratch);
            info.texture_applied = true;
        }
    } catch (const std::bad_alloc&) {
        return negaflow::core::KernelStatus::buffer_too_small;
    }

    const auto output_status = negaflow::core::validate_finite_pixels(input);
    if (output_status != negaflow::core::KernelStatus::ok) {
        return negaflow::core::KernelStatus::non_finite_output;
    }
    info.applied = true;
    return negaflow::core::KernelStatus::ok;
}

}  // namespace negaflow::imaging
