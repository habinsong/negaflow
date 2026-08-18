#include "film_scan_denoise_tile.h"

#include "film_scan_denoise_filters.h"
#include "film_scan_denoise_math.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>

namespace negaflow::imaging::film_scan_denoise_detail {

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

}  // namespace negaflow::imaging::film_scan_denoise_detail
