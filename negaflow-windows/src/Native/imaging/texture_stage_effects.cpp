#include "texture_stage_effects.h"

#include "texture_stage_gaussian.h"

#include "negaflow/core/parallel_rows.h"
#include "negaflow/imaging/coreimage_gaussian.h"
#include "negaflow/imaging/kernel_accelerator.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <new>
#include <vector>

namespace negaflow::imaging::texture_stage_detail {

void apply_unsharp(
    WorkingImage& image,
    const float radius,
    const float intensity,
    std::size_t& scratch_peak_bytes) {
    gaussian_transform(
        image,
        radius,
        GaussianEdgeMode::mirror,
        [](const negaflow::core::Rgba32F source) noexcept {
            return FilterSample{rgb(source), source.alpha};
        },
        [intensity](const negaflow::core::Rgba32F source,
                    const FilterSample blurred) noexcept {
            const Rgb original = rgb(source);
            return FilterSample{
                original + (original - blurred.color) * intensity,
                source.alpha,
            };
        },
        scratch_peak_bytes);
}

void apply_grain(WorkingImage& image, const float strength) noexcept {
    const float amount = strength * 0.055F;
    // **근사입니다**(루마·smoothstep). 해시는 uint32 이라 GPU 와 비트 일치합니다.
    // `ApproximateAcceleratorScope` 안에서만 돕니다 — 내보내기·골든은 CPU 그대로입니다.
    if (approximate_acceleration_allowed()) {
        if (const KernelAccelerator* const table = kernel_accelerator();
            table != nullptr && table->texture_grain != nullptr) {
            if (table->texture_grain(
                    reinterpret_cast<float*>(image.pixels.data()),
                    image.width,
                    image.height,
                    image.stride_pixels,
                    amount)) {
                return;
            }
        }
    }
    // The noise is a hash of the absolute pixel coordinate, not a running sequence, so
    // rows are independent and the split reproduces the same grain exactly.
    const std::uint64_t work_units =
        static_cast<std::uint64_t>(image.width) * static_cast<std::uint64_t>(image.height);
    negaflow::core::for_each_row_block(
        image.height,
        work_units,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
      for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
        auto* const row = image.pixels.data() +
            static_cast<std::size_t>(y) * image.stride_pixels;
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            const Rgb source = rgb(row[x]);
            const float luma = luminance(source);
            const float tone_weight =
                smoothstep(0.02F, 0.16F, luma) *
                (1.0F - smoothstep(0.82F, 1.0F, luma));
            const float noise =
                static_cast<float>(coordinate_hash(x, y) >> 8U) /
                    16777215.0F -
                0.5F;
            const float grain = noise * amount * tone_weight;
            const Rgb output = clamp_unit(
                source + Rgb{grain, grain, grain});
            row[x].red = output.red;
            row[x].green = output.green;
            row[x].blue = output.blue;
        }
      }
        });
}

void apply_negative_clarity(
    WorkingImage& image,
    const float clarity,
    std::size_t& scratch_peak_bytes) {
    const float amount = std::min(0.9F, -clarity * 0.8F);
    gaussian_transform(
        image,
        4.0F - clarity * 6.0F,
        GaussianEdgeMode::transparent,
        [](const negaflow::core::Rgba32F source) noexcept {
            return FilterSample{rgb(source), source.alpha};
        },
        [amount](const negaflow::core::Rgba32F source,
                 const FilterSample blurred) noexcept {
            return FilterSample{
                mix(rgb(source), blurred.color, amount),
                source.alpha + ((blurred.alpha - source.alpha) * amount),
            };
        },
        scratch_peak_bytes);
}

void apply_halation(
    WorkingImage& image,
    const float strength,
    std::size_t& scratch_peak_bytes) {
    gaussian_transform(
        image,
        5.0F + strength * 12.0F,
        GaussianEdgeMode::clamp,
        [](const negaflow::core::Rgba32F source) noexcept {
            const Rgb color = rgb(source);
            const float highlight_mask = clamp_unit(
                (luminance(color) - 0.5F) * 4.0F + 0.5F - 0.42F);
            return FilterSample{color * highlight_mask, source.alpha * highlight_mask};
        },
        [strength](const negaflow::core::Rgba32F source,
                   const FilterSample glow) noexcept {
            const Rgb original = rgb(source);
            const Rgb warm{
                glow.color.red * 0.85F * strength,
                glow.color.green * 0.40F * strength,
                glow.color.blue * 0.18F * strength,
            };
            return FilterSample{Rgb{
                original.red + warm.red - original.red * warm.red,
                original.green + warm.green - original.green * warm.green,
                original.blue + warm.blue - original.blue * warm.blue,
            }, source.alpha};
        },
        scratch_peak_bytes);
}

void apply_vignette(
    WorkingImage& image,
    const float vignette) noexcept {
    const float center_x = static_cast<float>(image.width) * 0.5F;
    const float center_y = static_cast<float>(image.height) * 0.5F;
    const float minimum_dimension =
        static_cast<float>(std::min(image.width, image.height));
    const float radius_zero = minimum_dimension * 0.34F;
    const float radius_one = minimum_dimension * 0.72F;
    const std::uint64_t work_units =
        static_cast<std::uint64_t>(image.width) * static_cast<std::uint64_t>(image.height);
    negaflow::core::for_each_row_block(
        image.height,
        work_units,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
      for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
        auto* const row = image.pixels.data() +
            static_cast<std::size_t>(y) * image.stride_pixels;
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            const float dx = static_cast<float>(x) + 0.5F - center_x;
            const float dy = static_cast<float>(y) + 0.5F - center_y;
            const float distance = std::sqrt(dx * dx + dy * dy);
            const float mask = clamp_unit(
                (distance - radius_zero) / (radius_one - radius_zero));
            const Rgb source = rgb(row[x]);
            Rgb adjusted{};
            if (vignette > 0.0F) {
                adjusted = source * (1.0F - vignette * 0.42F);
            } else {
                const float lift = -vignette * 0.16F;
                adjusted = clamp_unit(source + Rgb{lift, lift, lift});
            }
            const Rgb output = mix(source, adjusted, mask);
            row[x].red = output.red;
            row[x].green = output.green;
            row[x].blue = output.blue;
        }
      }
        });
}

} // namespace negaflow::imaging::texture_stage_detail
