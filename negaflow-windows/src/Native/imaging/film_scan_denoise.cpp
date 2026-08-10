#include "negaflow/imaging/film_scan_denoise.h"

#include "negaflow/core/parallel_rows.h"

#include <algorithm>
#include <array>
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

constexpr float gamma_lift_power = 0.45F;
constexpr float inverse_gamma_lift_power = 1.0F / gamma_lift_power;
constexpr float guided_epsilon = 0.001F;
constexpr int gaussian_radius = 4;
constexpr float gaussian_sigma = 1.3F;

struct Rgb final {
    float red{0.0F};
    float green{0.0F};
    float blue{0.0F};
};

struct Profile final {
    float luma_scale;
    float chroma_scale;
    float shadow_boost;
    float highlight_chroma;
    float highlight_luma_protect;
    bool monochrome;
};

struct Tile final {
    std::uint32_t source_x{0U};
    std::uint32_t source_y{0U};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::uint32_t core_x{0U};
    std::uint32_t core_y{0U};
    std::uint32_t core_width{0U};
    std::uint32_t core_height{0U};
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

[[nodiscard]] std::size_t pixel_count(
    const std::uint32_t width,
    const std::uint32_t height) {
    if (width == 0U || height == 0U ||
        static_cast<std::size_t>(width) >
            std::numeric_limits<std::size_t>::max() /
                static_cast<std::size_t>(height)) {
        throw std::bad_alloc{};
    }
    return static_cast<std::size_t>(width) * static_cast<std::size_t>(height);
}

[[nodiscard]] std::size_t index_of(
    const std::uint32_t x,
    const std::uint32_t y,
    const std::uint32_t width) noexcept {
    return static_cast<std::size_t>(y) * width + x;
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

[[nodiscard]] float luminance(const Rgb value) noexcept {
    return value.red * 0.2126F + value.green * 0.7152F +
           value.blue * 0.0722F;
}

[[nodiscard]] Rgb chroma(const Rgb value, const float luma) noexcept {
    return {
        value.red - luma,
        value.green - luma,
        value.blue - luma,
    };
}

[[nodiscard]] float length(const Rgb value) noexcept {
    return std::sqrt(
        value.red * value.red + value.green * value.green +
        value.blue * value.blue);
}

[[nodiscard]] float smoothstep(
    const float edge0,
    const float edge1,
    const float value) noexcept {
    const float t = clamp_unit((value - edge0) / (edge1 - edge0));
    return t * t * (3.0F - 2.0F * t);
}

[[nodiscard]] float mix(
    const float first,
    const float second,
    const float weight) noexcept {
    return first + (second - first) * weight;
}

[[nodiscard]] Rgb mix(
    const Rgb first,
    const Rgb second,
    const float weight) noexcept {
    return first + (second - first) * weight;
}

[[nodiscard]] Profile profile_for(
    const FilmScanDenoiseFilmProfile profile) noexcept {
    switch (profile) {
        case FilmScanDenoiseFilmProfile::color_negative:
            return {1.0F, 1.0F, 0.6F, 0.8F, 0.45F, false};
        case FilmScanDenoiseFilmProfile::color_positive:
            return {1.0F, 0.9F, 1.1F, 0.25F, 0.65F, false};
        case FilmScanDenoiseFilmProfile::black_and_white_negative:
            return {1.15F, 0.0F, 0.7F, 0.0F, 0.45F, true};
        case FilmScanDenoiseFilmProfile::black_and_white_positive:
            return {1.15F, 0.0F, 1.1F, 0.0F, 0.65F, true};
    }
    return {};
}

[[nodiscard]] std::vector<Rgb> extract_lifted_tile(
    const WorkingImage& image,
    const Tile& tile) {
    std::vector<Rgb> result(pixel_count(tile.width, tile.height));
    for (std::uint32_t y = 0U; y < tile.height; ++y) {
        const auto* const row = image.pixels.data() +
            static_cast<std::size_t>(tile.source_y + y) * image.stride_pixels;
        for (std::uint32_t x = 0U; x < tile.width; ++x) {
            const auto source = row[tile.source_x + x];
            result[index_of(x, y, tile.width)] = {
                std::pow(clamp_unit(source.red), gamma_lift_power),
                std::pow(clamp_unit(source.green), gamma_lift_power),
                std::pow(clamp_unit(source.blue), gamma_lift_power),
            };
        }
    }
    return result;
}

[[nodiscard]] std::vector<Rgb> gaussian_blur(
    const std::vector<Rgb>& source,
    const std::uint32_t width,
    const std::uint32_t height) {
    std::array<float, gaussian_radius * 2 + 1> weights{};
    float total = 0.0F;
    for (int offset = -gaussian_radius; offset <= gaussian_radius; ++offset) {
        const float value = std::exp(
            -static_cast<float>(offset * offset) /
            (2.0F * gaussian_sigma * gaussian_sigma));
        weights[static_cast<std::size_t>(offset + gaussian_radius)] = value;
        total += value;
    }
    for (float& weight : weights) {
        weight /= total;
    }

    std::vector<Rgb> horizontal(source.size());
    std::vector<Rgb> result(source.size());
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            Rgb value{};
            for (int offset = -gaussian_radius;
                 offset <= gaussian_radius;
                 ++offset) {
                const std::uint32_t sample_x = static_cast<std::uint32_t>(
                    std::clamp(
                        static_cast<int>(x) + offset,
                        0,
                        static_cast<int>(width) - 1));
                value = value + source[index_of(sample_x, y, width)] *
                    weights[static_cast<std::size_t>(offset + gaussian_radius)];
            }
            horizontal[index_of(x, y, width)] = value;
        }
    }
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            Rgb value{};
            for (int offset = -gaussian_radius;
                 offset <= gaussian_radius;
                 ++offset) {
                const std::uint32_t sample_y = static_cast<std::uint32_t>(
                    std::clamp(
                        static_cast<int>(y) + offset,
                        0,
                        static_cast<int>(height) - 1));
                value = value + horizontal[index_of(x, sample_y, width)] *
                    weights[static_cast<std::size_t>(offset + gaussian_radius)];
            }
            result[index_of(x, y, width)] = value;
        }
    }
    return result;
}

[[nodiscard]] float median9(std::array<float, 9U> values) noexcept {
    std::nth_element(values.begin(), values.begin() + 4, values.end());
    return values[4];
}

[[nodiscard]] std::vector<Rgb> median3(
    const std::vector<Rgb>& source,
    const std::uint32_t width,
    const std::uint32_t height) {
    std::vector<Rgb> result(source.size());
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            std::array<float, 9U> red{};
            std::array<float, 9U> green{};
            std::array<float, 9U> blue{};
            std::size_t cursor = 0U;
            for (int dy = -1; dy <= 1; ++dy) {
                const std::uint32_t sample_y = static_cast<std::uint32_t>(
                    std::clamp(
                        static_cast<int>(y) + dy,
                        0,
                        static_cast<int>(height) - 1));
                for (int dx = -1; dx <= 1; ++dx) {
                    const std::uint32_t sample_x = static_cast<std::uint32_t>(
                        std::clamp(
                            static_cast<int>(x) + dx,
                            0,
                            static_cast<int>(width) - 1));
                    const Rgb sample = source[index_of(sample_x, sample_y, width)];
                    red[cursor] = sample.red;
                    green[cursor] = sample.green;
                    blue[cursor] = sample.blue;
                    ++cursor;
                }
            }
            result[index_of(x, y, width)] = {
                median9(red),
                median9(green),
                median9(blue),
            };
        }
    }
    return result;
}

[[nodiscard]] std::vector<float> box_blur(
    const std::vector<float>& source,
    const std::uint32_t width,
    const std::uint32_t height,
    const int radius) {
    std::vector<float> horizontal(source.size());
    std::vector<float> result(source.size());
    const float inverse = 1.0F / static_cast<float>(radius * 2 + 1);

    for (std::uint32_t y = 0U; y < height; ++y) {
        float sum = 0.0F;
        for (int offset = -radius; offset <= radius; ++offset) {
            const std::uint32_t sample_x = static_cast<std::uint32_t>(
                std::clamp(offset, 0, static_cast<int>(width) - 1));
            sum += source[index_of(sample_x, y, width)];
        }
        for (std::uint32_t x = 0U; x < width; ++x) {
            horizontal[index_of(x, y, width)] = sum * inverse;
            const std::uint32_t remove_x = static_cast<std::uint32_t>(
                std::clamp(
                    static_cast<int>(x) - radius,
                    0,
                    static_cast<int>(width) - 1));
            const std::uint32_t add_x = static_cast<std::uint32_t>(
                std::clamp(
                    static_cast<int>(x) + radius + 1,
                    0,
                    static_cast<int>(width) - 1));
            sum += source[index_of(add_x, y, width)] -
                   source[index_of(remove_x, y, width)];
        }
    }
    for (std::uint32_t x = 0U; x < width; ++x) {
        float sum = 0.0F;
        for (int offset = -radius; offset <= radius; ++offset) {
            const std::uint32_t sample_y = static_cast<std::uint32_t>(
                std::clamp(offset, 0, static_cast<int>(height) - 1));
            sum += horizontal[index_of(x, sample_y, width)];
        }
        for (std::uint32_t y = 0U; y < height; ++y) {
            result[index_of(x, y, width)] = sum * inverse;
            const std::uint32_t remove_y = static_cast<std::uint32_t>(
                std::clamp(
                    static_cast<int>(y) - radius,
                    0,
                    static_cast<int>(height) - 1));
            const std::uint32_t add_y = static_cast<std::uint32_t>(
                std::clamp(
                    static_cast<int>(y) + radius + 1,
                    0,
                    static_cast<int>(height) - 1));
            sum += horizontal[index_of(x, add_y, width)] -
                   horizontal[index_of(x, remove_y, width)];
        }
    }
    return result;
}

[[nodiscard]] std::vector<Rgb> box_blur(
    const std::vector<Rgb>& source,
    const std::uint32_t width,
    const std::uint32_t height,
    const int radius) {
    std::vector<Rgb> horizontal(source.size());
    std::vector<Rgb> result(source.size());
    const float inverse = 1.0F / static_cast<float>(radius * 2 + 1);

    for (std::uint32_t y = 0U; y < height; ++y) {
        Rgb sum{};
        for (int offset = -radius; offset <= radius; ++offset) {
            const std::uint32_t sample_x = static_cast<std::uint32_t>(
                std::clamp(offset, 0, static_cast<int>(width) - 1));
            sum = sum + source[index_of(sample_x, y, width)];
        }
        for (std::uint32_t x = 0U; x < width; ++x) {
            horizontal[index_of(x, y, width)] = sum * inverse;
            const std::uint32_t remove_x = static_cast<std::uint32_t>(
                std::clamp(
                    static_cast<int>(x) - radius,
                    0,
                    static_cast<int>(width) - 1));
            const std::uint32_t add_x = static_cast<std::uint32_t>(
                std::clamp(
                    static_cast<int>(x) + radius + 1,
                    0,
                    static_cast<int>(width) - 1));
            sum = sum + source[index_of(add_x, y, width)] -
                  source[index_of(remove_x, y, width)];
        }
    }
    for (std::uint32_t x = 0U; x < width; ++x) {
        Rgb sum{};
        for (int offset = -radius; offset <= radius; ++offset) {
            const std::uint32_t sample_y = static_cast<std::uint32_t>(
                std::clamp(offset, 0, static_cast<int>(height) - 1));
            sum = sum + horizontal[index_of(x, sample_y, width)];
        }
        for (std::uint32_t y = 0U; y < height; ++y) {
            result[index_of(x, y, width)] = sum * inverse;
            const std::uint32_t remove_y = static_cast<std::uint32_t>(
                std::clamp(
                    static_cast<int>(y) - radius,
                    0,
                    static_cast<int>(height) - 1));
            const std::uint32_t add_y = static_cast<std::uint32_t>(
                std::clamp(
                    static_cast<int>(y) + radius + 1,
                    0,
                    static_cast<int>(height) - 1));
            sum = sum + horizontal[index_of(x, add_y, width)] -
                  horizontal[index_of(x, remove_y, width)];
        }
    }
    return result;
}

[[nodiscard]] std::vector<Rgb> guided_base(
    const std::vector<Rgb>& source,
    const std::vector<float>& guide,
    const std::uint32_t width,
    const std::uint32_t height,
    const int radius) {
    std::vector<float> guide_squared(guide.size());
    std::vector<Rgb> guide_product(source.size());
    for (std::size_t index = 0U; index < source.size(); ++index) {
        guide_squared[index] = guide[index] * guide[index];
        guide_product[index] = source[index] * guide[index];
    }

    const std::vector<float> mean_guide =
        box_blur(guide, width, height, radius);
    const std::vector<Rgb> mean_source =
        box_blur(source, width, height, radius);
    const std::vector<float> mean_guide_squared =
        box_blur(guide_squared, width, height, radius);
    const std::vector<Rgb> mean_guide_product =
        box_blur(guide_product, width, height, radius);

    std::vector<Rgb> coefficient_a(source.size());
    std::vector<Rgb> coefficient_b(source.size());
    for (std::size_t index = 0U; index < source.size(); ++index) {
        const float variance = std::max(
            0.0F,
            mean_guide_squared[index] -
                mean_guide[index] * mean_guide[index]);
        const Rgb covariance =
            mean_guide_product[index] - mean_source[index] * mean_guide[index];
        coefficient_a[index] = covariance * (1.0F / (variance + guided_epsilon));
        coefficient_b[index] =
            mean_source[index] - coefficient_a[index] * mean_guide[index];
    }

    const std::vector<Rgb> mean_a =
        box_blur(coefficient_a, width, height, radius);
    const std::vector<Rgb> mean_b =
        box_blur(coefficient_b, width, height, radius);
    std::vector<Rgb> result(source.size());
    for (std::size_t index = 0U; index < source.size(); ++index) {
        result[index] = clamp_unit(mean_a[index] * guide[index] + mean_b[index]);
    }
    return result;
}

[[nodiscard]] Tile make_tile(
    const WorkingImage& image,
    const std::uint32_t core_x,
    const std::uint32_t core_y) noexcept {
    const std::uint32_t core_width =
        std::min(film_scan_denoise_tile_side, image.width - core_x);
    const std::uint32_t core_height =
        std::min(film_scan_denoise_tile_side, image.height - core_y);
    const std::uint32_t source_x =
        core_x > film_scan_denoise_tile_apron
            ? core_x - film_scan_denoise_tile_apron
            : 0U;
    const std::uint32_t source_y =
        core_y > film_scan_denoise_tile_apron
            ? core_y - film_scan_denoise_tile_apron
            : 0U;
    const std::uint32_t source_right = std::min(
        image.width,
        core_x + core_width + film_scan_denoise_tile_apron);
    const std::uint32_t source_bottom = std::min(
        image.height,
        core_y + core_height + film_scan_denoise_tile_apron);
    return {
        source_x,
        source_y,
        source_right - source_x,
        source_bottom - source_y,
        core_x - source_x,
        core_y - source_y,
        core_width,
        core_height,
    };
}

void process_tile(
    const WorkingImage& image,
    const FilmScanDenoiseParameters& parameters,
    const Profile& profile,
    const Tile& tile,
    std::vector<Rgb>& output) {
    const std::vector<Rgb> source = extract_lifted_tile(image, tile);
    const std::vector<Rgb> fine = gaussian_blur(source, tile.width, tile.height);
    std::vector<float> guide(source.size());
    for (std::size_t index = 0U; index < source.size(); ++index) {
        guide[index] = luminance(fine[index]);
    }
    const std::vector<Rgb> middle =
        guided_base(source, guide, tile.width, tile.height, 3);
    const std::vector<Rgb> coarse =
        guided_base(source, guide, tile.width, tile.height, 7);
    const std::vector<Rgb> med3 = median3(source, tile.width, tile.height);
    const std::vector<Rgb> med5 = median3(med3, tile.width, tile.height);

    const float strength = parameters.strength;
    const float luma_gate = parameters.axes.luma * 2.0F;
    const float chroma_gate = parameters.axes.chroma * 2.0F;
    const float dark_tone_scale = parameters.axes.dark_tone * 2.0F;
    const float detail_scale = 1.5F - parameters.axes.detail;
    const float base_luma_threshold = std::max(
        0.065F * std::pow(strength, 1.25F) * profile.luma_scale * luma_gate,
        1.0e-6F);
    const float base_chroma_threshold = std::max(
        0.14F * std::pow(strength, 1.1F) * profile.chroma_scale * chroma_gate,
        1.0e-6F);
    const float impulse_luma_threshold = luma_gate > 1.0e-3F
        ? (0.10F - 0.055F * strength) / std::min(luma_gate, 1.0F)
        : 10.0F;
    const float impulse_chroma_threshold = chroma_gate > 1.0e-3F
        ? (0.09F - 0.05F * strength) / std::min(chroma_gate, 1.0F)
        : 10.0F;

    for (std::uint32_t core_y = 0U; core_y < tile.core_height; ++core_y) {
        const std::uint32_t local_y = tile.core_y + core_y;
        for (std::uint32_t core_x = 0U; core_x < tile.core_width; ++core_x) {
            const std::uint32_t local_x = tile.core_x + core_x;
            const std::size_t local_index =
                index_of(local_x, local_y, tile.width);
            const Rgb original = source[local_index];
            const Rgb median_three = med3[local_index];
            const Rgb median_five = med5[local_index];
            const Rgb fine_value = fine[local_index];
            const Rgb middle_value = middle[local_index];
            const Rgb coarse_value = coarse[local_index];

            const float y0 = luminance(original);
            const float ym3 = luminance(median_three);
            const float ym5 = luminance(median_five);
            const float y1 = luminance(fine_value);
            const float y2 = luminance(middle_value);
            const float y3 = luminance(coarse_value);
            const Rgb c0 = chroma(original, y0);
            const Rgb cm3 = chroma(median_three, ym3);
            const Rgb c1 = chroma(fine_value, y1);
            const Rgb c2 = chroma(middle_value, y2);
            const Rgb c3 = chroma(coarse_value, y3);

            const float shadow = 1.0F - smoothstep(0.16F, 0.42F, y3);
            const float near_clip = smoothstep(0.88F, 0.97F, y3);
            const float grain_zone =
                smoothstep(0.30F, 0.50F, y3) *
                (1.0F - smoothstep(0.75F, 0.92F, y3));
            const float grain_weight =
                parameters.axes.grain_protect * grain_zone;

            const float consistency = 1.0F - smoothstep(
                0.015F,
                0.055F,
                std::abs(ym3 - ym5));
            const float impulse_luma_weight = std::min(
                smoothstep(
                    impulse_luma_threshold,
                    impulse_luma_threshold * 1.9F,
                    std::abs(y0 - ym3)) *
                    consistency * (1.0F - 0.85F * grain_weight),
                0.92F);
            const float fixed_luma = mix(y0, ym3, impulse_luma_weight);
            const float impulse_chroma_weight = std::min(
                smoothstep(
                    impulse_chroma_threshold,
                    impulse_chroma_threshold * 1.9F,
                    length(c0 - cm3)) *
                    consistency,
                0.92F);
            const Rgb fixed_chroma = mix(c0, cm3, impulse_chroma_weight);

            float luma_threshold =
                base_luma_threshold *
                (1.0F + profile.shadow_boost * dark_tone_scale * shadow) *
                (1.0F - profile.highlight_luma_protect * near_clip);
            float chroma_threshold =
                base_chroma_threshold *
                (1.0F + 0.35F * dark_tone_scale * shadow +
                 profile.highlight_chroma * near_clip);
            luma_threshold *= 1.0F - 0.95F * grain_weight;
            luma_threshold *= detail_scale;

            const float luma_structure = std::abs(y1 - y3);
            const float chroma_structure = length(c1 - c3);
            luma_threshold *= 1.0F - 0.90F * smoothstep(
                0.018F * detail_scale,
                0.055F * detail_scale,
                luma_structure + 0.5F * chroma_structure);
            chroma_threshold *= 1.0F - 0.93F * smoothstep(
                0.045F * detail_scale,
                0.120F * detail_scale,
                chroma_structure + 0.5F * luma_structure);

            const float detail_one = fixed_luma - y1;
            const float detail_two = y1 - y2;
            const float detail_three = y2 - y3;
            const float output_luma =
                y3 +
                detail_three * smoothstep(
                    0.55F * luma_threshold * 0.10F,
                    1.5F * luma_threshold * 0.10F,
                    std::abs(detail_three)) +
                detail_two * smoothstep(
                    0.55F * luma_threshold * 0.55F,
                    1.5F * luma_threshold * 0.55F,
                    std::abs(detail_two)) +
                detail_one * smoothstep(
                    0.55F * luma_threshold,
                    1.5F * luma_threshold,
                    std::abs(detail_one));

            Rgb output_chroma = c0;
            if (!profile.monochrome) {
                const Rgb detail_chroma_one = fixed_chroma - c1;
                const Rgb detail_chroma_two = c1 - c2;
                const Rgb detail_chroma_three = c2 - c3;
                output_chroma =
                    c3 +
                    detail_chroma_three * smoothstep(
                        0.55F * chroma_threshold * 0.45F,
                        1.5F * chroma_threshold * 0.45F,
                        length(detail_chroma_three)) +
                    detail_chroma_two * smoothstep(
                        0.55F * chroma_threshold * 0.80F,
                        1.5F * chroma_threshold * 0.80F,
                        length(detail_chroma_two)) +
                    detail_chroma_one * smoothstep(
                        0.55F * chroma_threshold,
                        1.5F * chroma_threshold,
                        length(detail_chroma_one));
            }

            const Rgb lifted_output = clamp_unit(
                Rgb{output_luma, output_luma, output_luma} + output_chroma);
            const std::uint32_t output_x = tile.source_x + local_x;
            const std::uint32_t output_y = tile.source_y + local_y;
            output[index_of(output_x, output_y, image.width)] = {
                std::pow(lifted_output.red, inverse_gamma_lift_power),
                std::pow(lifted_output.green, inverse_gamma_lift_power),
                std::pow(lifted_output.blue, inverse_gamma_lift_power),
            };
        }
    }
}

}  // namespace

bool valid_film_scan_denoise_parameters(
    const FilmScanDenoiseParameters& parameters) noexcept {
    const auto unit = [](const float value) noexcept {
        return std::isfinite(value) && value >= 0.0F && value <= 1.0F;
    };
    return unit(parameters.strength) && unit(parameters.axes.luma) &&
           unit(parameters.axes.chroma) && unit(parameters.axes.dark_tone) &&
           unit(parameters.axes.detail) &&
           unit(parameters.axes.grain_protect) &&
           static_cast<std::uint8_t>(parameters.film_profile) <=
               static_cast<std::uint8_t>(
                   FilmScanDenoiseFilmProfile::black_and_white_positive);
}

FilmScanDenoiseResult apply_film_scan_denoise(
    WorkingImage image,
    const FilmScanDenoiseParameters& parameters,
    const negaflow::core::CancelFlag cancel) noexcept {
    FilmScanDenoiseResult result{};
    result.image = std::move(image);
    if (!valid_film_scan_denoise_parameters(parameters)) {
        discard_pixels(result.image);
        return result;
    }

    result.info.kernel_status =
        negaflow::core::validate_finite_pixels(const_view(result.image));
    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = FilmScanDenoiseStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }
    if (parameters.strength <= film_scan_denoise_identity_threshold) {
        result.status = FilmScanDenoiseStatus::ok;
        return result;
    }

    try {
        std::vector<Rgb> output(
            pixel_count(result.image.width, result.image.height));
        result.info.output_scratch_bytes = output.size() * sizeof(Rgb);
        const Profile profile = profile_for(parameters.film_profile);

        // Each tile reads an apron but writes only its own core, and the cores are
        // disjoint. That is what makes the tile rows independent, so splitting them
        // across cores changes nothing but the wall clock. On a 17 MP scan this stage
        // was by far the most expensive in the whole develop.
        const std::uint32_t tile_rows =
            (result.image.height + film_scan_denoise_tile_side - 1U) /
            film_scan_denoise_tile_side;
        std::atomic<std::uint32_t> tiles_processed{0U};
        std::atomic<bool> cancelled{false};
        const std::uint64_t work_units =
            static_cast<std::uint64_t>(result.image.width) *
            static_cast<std::uint64_t>(result.image.height);
        negaflow::core::for_each_row_block(
            tile_rows,
            work_units,
            [&](const std::uint32_t first_tile_row,
                const std::uint32_t tile_row_count) noexcept {
                std::uint32_t processed = 0U;
                for (std::uint32_t index = first_tile_row;
                     index < first_tile_row + tile_row_count;
                     ++index) {
                    if (cancel.requested()) {
                        cancelled.store(true, std::memory_order_relaxed);
                        break;
                    }
                    const std::uint32_t core_y =
                        index * film_scan_denoise_tile_side;
                    for (std::uint32_t core_x = 0U;
                         core_x < result.image.width;
                         core_x += film_scan_denoise_tile_side) {
                        process_tile(
                            result.image,
                            parameters,
                            profile,
                            make_tile(result.image, core_x, core_y),
                            output);
                        ++processed;
                    }
                }
                tiles_processed.fetch_add(processed, std::memory_order_relaxed);
            });
        if (cancelled.load(std::memory_order_relaxed)) {
            result.status = FilmScanDenoiseStatus::cancelled;
            discard_pixels(result.image);
            return result;
        }
        result.info.tiles_processed = tiles_processed.load(std::memory_order_relaxed);

        negaflow::core::for_each_row_block(
            result.image.height,
            work_units,
            [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
                for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                    auto* const row = result.image.pixels.data() +
                        static_cast<std::size_t>(y) * result.image.stride_pixels;
                    for (std::uint32_t x = 0U; x < result.image.width; ++x) {
                        const Rgb value =
                            output[index_of(x, y, result.image.width)];
                        row[x].red = value.red;
                        row[x].green = value.green;
                        row[x].blue = value.blue;
                    }
                }
            });
        result.info.applied = true;
        result.status = FilmScanDenoiseStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.status = FilmScanDenoiseStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    } catch (...) {
        result.status = FilmScanDenoiseStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    }
}

const char* film_scan_denoise_status_name(
    const FilmScanDenoiseStatus status) noexcept {
    switch (status) {
        case FilmScanDenoiseStatus::cancelled:
            return "cancelled";
        case FilmScanDenoiseStatus::ok:
            return "ok";
        case FilmScanDenoiseStatus::invalid_parameter:
            return "invalid_parameter";
        case FilmScanDenoiseStatus::kernel_failed:
            return "kernel_failed";
        case FilmScanDenoiseStatus::allocation_failed:
            return "allocation_failed";
    }
    return "unknown";
}

}  // namespace negaflow::imaging
