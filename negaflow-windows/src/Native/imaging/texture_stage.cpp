#include "negaflow/imaging/texture_stage.h"

#include "negaflow/core/parallel_rows.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

struct Rgb final {
    float red;
    float green;
    float blue;
};

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
}

[[nodiscard]] negaflow::core::ConstImageView const_view(
    const WorkingImage& image) noexcept {
    return {
        image.pixels.data(),
        image.pixels.size(),
        image.width,
        image.height,
        image.stride_pixels,
    };
}

[[nodiscard]] std::size_t checked_count(
    const std::uint32_t width,
    const std::uint32_t height) {
    if (width == 0U || height == 0U ||
        static_cast<std::size_t>(width) >
            std::numeric_limits<std::size_t>::max() /
                static_cast<std::size_t>(height)) {
        throw std::bad_alloc{};
    }
    return static_cast<std::size_t>(width) * height;
}

[[nodiscard]] std::size_t index_of(
    const std::uint32_t x,
    const std::uint32_t y,
    const std::uint32_t width) noexcept {
    return static_cast<std::size_t>(y) * width + x;
}

[[nodiscard]] Rgb rgb(const negaflow::core::Rgba32F value) noexcept {
    return {value.red, value.green, value.blue};
}

[[nodiscard]] Rgb operator+(const Rgb left, const Rgb right) noexcept {
    return {
        left.red + right.red,
        left.green + right.green,
        left.blue + right.blue,
    };
}

[[nodiscard]] Rgb operator-(const Rgb left, const Rgb right) noexcept {
    return {
        left.red - right.red,
        left.green - right.green,
        left.blue - right.blue,
    };
}

[[nodiscard]] Rgb operator*(const Rgb value, const float scale) noexcept {
    return {
        value.red * scale,
        value.green * scale,
        value.blue * scale,
    };
}

[[nodiscard]] float clamp_unit(const float value) noexcept {
    return std::clamp(value, 0.0F, 1.0F);
}

[[nodiscard]] Rgb clamp_unit(const Rgb value) noexcept {
    return {
        clamp_unit(value.red),
        clamp_unit(value.green),
        clamp_unit(value.blue),
    };
}

[[nodiscard]] Rgb mix(
    const Rgb first,
    const Rgb second,
    const float weight) noexcept {
    return first + (second - first) * weight;
}

[[nodiscard]] float luminance(const Rgb value) noexcept {
    return value.red * 0.2126F + value.green * 0.7152F +
           value.blue * 0.0722F;
}

[[nodiscard]] float smoothstep(
    const float edge0,
    const float edge1,
    const float value) noexcept {
    const float t = clamp_unit((value - edge0) / (edge1 - edge0));
    return t * t * (3.0F - 2.0F * t);
}

[[nodiscard]] std::uint32_t coordinate_hash(
    const std::uint32_t x,
    const std::uint32_t y) noexcept {
    std::uint32_t value = x * 0x9e3779b9U ^ y * 0x85ebca6bU ^ 0xc2b2ae35U;
    value ^= value >> 16U;
    value *= 0x7feb352dU;
    value ^= value >> 15U;
    value *= 0x846ca68bU;
    value ^= value >> 16U;
    return value;
}

template <typename Extract, typename Combine>
void gaussian_transform(
    WorkingImage& image,
    const float sigma,
    Extract extract,
    Combine combine,
    std::size_t& scratch_peak_bytes) {
    const int radius = std::max(1, static_cast<int>(std::ceil(3.0F * sigma)));
    std::vector<float> weights(static_cast<std::size_t>(radius * 2 + 1));
    float weight_total = 0.0F;
    for (int offset = -radius; offset <= radius; ++offset) {
        const float weight = std::exp(
            -static_cast<float>(offset * offset) /
            (2.0F * sigma * sigma));
        weights[static_cast<std::size_t>(offset + radius)] = weight;
        weight_total += weight;
    }
    for (float& weight : weights) {
        weight /= weight_total;
    }

    std::vector<Rgb> output(checked_count(image.width, image.height));
    const std::size_t output_bytes = output.size() * sizeof(Rgb);

    // Same shape as FilmScanDenoise: a tile reads an apron of `radius` but writes only its
    // own core into `output`, and the cores are disjoint. `image` is read-only until the
    // write-back below, so the tile rows run concurrently without changing a result.
    const std::uint32_t tile_rows =
        (image.height + texture_stage_tile_side - 1U) / texture_stage_tile_side;
    std::atomic<std::size_t> peak_scratch{scratch_peak_bytes};
    const std::uint64_t work_units =
        static_cast<std::uint64_t>(image.width) * static_cast<std::uint64_t>(image.height);
    negaflow::core::for_each_row_block(
        tile_rows,
        work_units,
        [&](const std::uint32_t first_tile_row,
            const std::uint32_t tile_row_count) noexcept {
      for (std::uint32_t tile_row = first_tile_row;
           tile_row < first_tile_row + tile_row_count;
           ++tile_row) {
        const std::uint32_t core_y = tile_row * texture_stage_tile_side;
        const std::uint32_t core_height =
            std::min(texture_stage_tile_side, image.height - core_y);
        for (std::uint32_t core_x = 0U;
             core_x < image.width;
             core_x += texture_stage_tile_side) {
            const std::uint32_t core_width =
                std::min(texture_stage_tile_side, image.width - core_x);
            const std::uint32_t source_x = core_x > static_cast<std::uint32_t>(radius)
                ? core_x - static_cast<std::uint32_t>(radius)
                : 0U;
            const std::uint32_t source_y = core_y > static_cast<std::uint32_t>(radius)
                ? core_y - static_cast<std::uint32_t>(radius)
                : 0U;
            const std::uint32_t source_right = std::min(
                image.width,
                core_x + core_width + static_cast<std::uint32_t>(radius));
            const std::uint32_t source_bottom = std::min(
                image.height,
                core_y + core_height + static_cast<std::uint32_t>(radius));
            const std::uint32_t tile_width = source_right - source_x;
            const std::uint32_t tile_height = source_bottom - source_y;
            const std::size_t tile_count = checked_count(tile_width, tile_height);
            std::vector<Rgb> source(tile_count);
            std::vector<Rgb> horizontal(tile_count);
            std::vector<Rgb> blurred(tile_count);
            // Reduced with an atomic maximum so the reported peak is the same figure the
            // sequential loop produced, whatever order the tiles finish in.
            const std::size_t tile_scratch =
                output_bytes + tile_count * sizeof(Rgb) * 3U +
                weights.size() * sizeof(float);
            std::size_t seen = peak_scratch.load(std::memory_order_relaxed);
            while (tile_scratch > seen &&
                   !peak_scratch.compare_exchange_weak(
                       seen,
                       tile_scratch,
                       std::memory_order_relaxed,
                       std::memory_order_relaxed)) {
            }

            for (std::uint32_t y = 0U; y < tile_height; ++y) {
                const auto* const row = image.pixels.data() +
                    static_cast<std::size_t>(source_y + y) * image.stride_pixels;
                for (std::uint32_t x = 0U; x < tile_width; ++x) {
                    source[index_of(x, y, tile_width)] =
                        extract(rgb(row[source_x + x]));
                }
            }
            for (std::uint32_t y = 0U; y < tile_height; ++y) {
                for (std::uint32_t x = 0U; x < tile_width; ++x) {
                    Rgb value{};
                    for (int offset = -radius; offset <= radius; ++offset) {
                        const auto sample_x = static_cast<std::uint32_t>(std::clamp(
                            static_cast<int>(x) + offset,
                            0,
                            static_cast<int>(tile_width) - 1));
                        value = value +
                            source[index_of(sample_x, y, tile_width)] *
                            weights[static_cast<std::size_t>(offset + radius)];
                    }
                    horizontal[index_of(x, y, tile_width)] = value;
                }
            }
            for (std::uint32_t y = 0U; y < tile_height; ++y) {
                for (std::uint32_t x = 0U; x < tile_width; ++x) {
                    Rgb value{};
                    for (int offset = -radius; offset <= radius; ++offset) {
                        const auto sample_y = static_cast<std::uint32_t>(std::clamp(
                            static_cast<int>(y) + offset,
                            0,
                            static_cast<int>(tile_height) - 1));
                        value = value +
                            horizontal[index_of(x, sample_y, tile_width)] *
                            weights[static_cast<std::size_t>(offset + radius)];
                    }
                    blurred[index_of(x, y, tile_width)] = value;
                }
            }

            const std::uint32_t local_core_x = core_x - source_x;
            const std::uint32_t local_core_y = core_y - source_y;
            for (std::uint32_t y = 0U; y < core_height; ++y) {
                const auto* const row = image.pixels.data() +
                    static_cast<std::size_t>(core_y + y) * image.stride_pixels;
                for (std::uint32_t x = 0U; x < core_width; ++x) {
                    output[index_of(core_x + x, core_y + y, image.width)] =
                        combine(
                            rgb(row[core_x + x]),
                            blurred[index_of(
                                local_core_x + x,
                                local_core_y + y,
                                tile_width)]);
                }
            }
        }
      }
        });
    scratch_peak_bytes = peak_scratch.load(std::memory_order_relaxed);

    negaflow::core::for_each_row_block(
        image.height,
        work_units,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                auto* const row = image.pixels.data() +
                    static_cast<std::size_t>(y) * image.stride_pixels;
                for (std::uint32_t x = 0U; x < image.width; ++x) {
                    const Rgb value = output[index_of(x, y, image.width)];
                    row[x].red = value.red;
                    row[x].green = value.green;
                    row[x].blue = value.blue;
                }
            }
        });
}

void apply_unsharp(
    WorkingImage& image,
    const float radius,
    const float intensity,
    std::size_t& scratch_peak_bytes) {
    gaussian_transform(
        image,
        radius,
        [](const Rgb source) noexcept { return source; },
        [intensity](const Rgb source, const Rgb blurred) noexcept {
            return source + (source - blurred) * intensity;
        },
        scratch_peak_bytes);
}

void apply_grain(WorkingImage& image, const float strength) noexcept {
    const float amount = strength * 0.055F;
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
        [](const Rgb source) noexcept { return source; },
        [amount](const Rgb source, const Rgb blurred) noexcept {
            return mix(source, blurred, amount);
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
        [](const Rgb source) noexcept {
            const float highlight_mask = clamp_unit(
                (luminance(source) - 0.5F) * 4.0F + 0.5F - 0.42F);
            return source * highlight_mask;
        },
        [strength](const Rgb source, const Rgb glow) noexcept {
            const Rgb warm{
                glow.red * 0.85F * strength,
                glow.green * 0.40F * strength,
                glow.blue * 0.18F * strength,
            };
            return Rgb{
                source.red + warm.red - source.red * warm.red,
                source.green + warm.green - source.green * warm.green,
                source.blue + warm.blue - source.blue * warm.blue,
            };
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

}  // namespace

bool valid_texture_stage_parameters(
    const TextureStageParameters& parameters) noexcept {
    const auto normalized = [](const float value) noexcept {
        return std::isfinite(value) && value >= 0.0F && value <= 1.0F;
    };
    const auto signed_normalized = [](const float value) noexcept {
        return std::isfinite(value) && value >= -1.0F && value <= 1.0F;
    };
    return normalized(parameters.grain) &&
           normalized(parameters.sharpness) &&
           normalized(parameters.halation) &&
           signed_normalized(parameters.clarity) &&
           signed_normalized(parameters.vignette);
}

TextureStageResult apply_texture_stage(
    WorkingImage image,
    const TextureStageParameters& parameters) noexcept {
    TextureStageResult result{};
    result.image = std::move(image);
    if (!valid_texture_stage_parameters(parameters)) {
        discard_pixels(result.image);
        return result;
    }
    result.info.kernel_status =
        negaflow::core::validate_finite_pixels(const_view(result.image));
    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = TextureStageStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }

    try {
        if (parameters.sharpness > texture_stage_identity_threshold) {
            apply_unsharp(
                result.image,
                1.0F + parameters.sharpness * 1.2F,
                0.18F + parameters.sharpness * 0.42F,
                result.info.output_scratch_peak_bytes);
            result.info.sharpness_applied = true;
        }
        if (parameters.grain > texture_stage_identity_threshold) {
            apply_grain(result.image, parameters.grain);
            result.info.grain_applied = true;
        }
        if (std::abs(parameters.clarity) >
            texture_stage_identity_threshold) {
            if (parameters.clarity > 0.0F) {
                apply_unsharp(
                    result.image,
                    6.0F + parameters.clarity * 5.0F,
                    0.10F + parameters.clarity * 0.18F,
                    result.info.output_scratch_peak_bytes);
            } else {
                apply_negative_clarity(
                    result.image,
                    parameters.clarity,
                    result.info.output_scratch_peak_bytes);
            }
            result.info.clarity_applied = true;
        }
        if (parameters.halation > texture_stage_identity_threshold) {
            apply_halation(
                result.image,
                parameters.halation,
                result.info.output_scratch_peak_bytes);
            result.info.halation_applied = true;
        }
        if (std::abs(parameters.vignette) >
            texture_stage_identity_threshold) {
            apply_vignette(result.image, parameters.vignette);
            result.info.vignette_applied = true;
        }
        result.info.applied =
            result.info.grain_applied || result.info.sharpness_applied ||
            result.info.halation_applied || result.info.clarity_applied ||
            result.info.vignette_applied;
        result.status = TextureStageStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.status = TextureStageStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    } catch (...) {
        result.status = TextureStageStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    }
}

const char* texture_stage_status_name(
    const TextureStageStatus status) noexcept {
    switch (status) {
        case TextureStageStatus::ok:
            return "ok";
        case TextureStageStatus::invalid_parameter:
            return "invalid_parameter";
        case TextureStageStatus::kernel_failed:
            return "kernel_failed";
        case TextureStageStatus::allocation_failed:
            return "allocation_failed";
    }
    return "unknown";
}

}  // namespace negaflow::imaging
