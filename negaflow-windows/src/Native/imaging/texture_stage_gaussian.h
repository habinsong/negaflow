#pragma once

/* 한 번 훑고 다시 합치는 가우시안 골격입니다. 무엇을 뽑고(extract) 무엇과 합칠지
   (combine) 는 호출부가 정하므로 템플릿으로 두고 헤더에 정의합니다. */

#include "texture_stage_math.h"

#include "negaflow/core/parallel_rows.h"
#include "negaflow/imaging/coreimage_gaussian.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <new>
#include <vector>

namespace negaflow::imaging::texture_stage_detail {

template <typename Extract, typename Combine>
void gaussian_transform(
    WorkingImage& image,
    const float sigma,
    const GaussianEdgeMode edge_mode,
    Extract extract,
    Combine combine,
    std::size_t& scratch_peak_bytes) {
    const float effective_sigma = coreimage_gaussian_effective_sigma(sigma);
    const int radius = std::max(1, coreimage_gaussian_support_radius(sigma));
    std::vector<float> weights(static_cast<std::size_t>(radius * 2 + 1));
    float weight_total = 0.0F;
    for (int offset = -radius; offset <= radius; ++offset) {
        const float weight = std::exp(
            -static_cast<float>(offset * offset) /
            (2.0F * effective_sigma * effective_sigma));
        weights[static_cast<std::size_t>(offset + radius)] = weight;
        weight_total += weight;
    }
    for (float& weight : weights) {
        weight /= weight_total;
    }
    const auto coordinate = [edge_mode](const int candidate, const int limit) noexcept {
        if (edge_mode != GaussianEdgeMode::mirror || limit <= 1) {
            return std::clamp(candidate, 0, limit - 1);
        }
        // Core Image mirrors the boundary pixel itself: -1 → 0 and limit → limit - 1.
        const int period = limit * 2;
        int folded = candidate % period;
        if (folded < 0) folded += period;
        return folded < limit ? folded : period - 1 - folded;
    };

    std::vector<FilterSample> output(checked_count(image.width, image.height));
    const std::size_t output_bytes = output.size() * sizeof(FilterSample);

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
            std::vector<FilterSample> source(tile_count);
            std::vector<FilterSample> horizontal(tile_count);
            std::vector<FilterSample> blurred(tile_count);
            // Reduced with an atomic maximum so the reported peak is the same figure the
            // sequential loop produced, whatever order the tiles finish in.
            const std::size_t tile_scratch =
                output_bytes + tile_count * sizeof(FilterSample) * 3U +
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
                    source[index_of(x, y, tile_width)] = extract(row[source_x + x]);
                }
            }
            for (std::uint32_t y = 0U; y < tile_height; ++y) {
                for (std::uint32_t x = 0U; x < tile_width; ++x) {
                    FilterSample value{};
                    for (int offset = -radius; offset <= radius; ++offset) {
                        const int candidate_x = static_cast<int>(x) + offset;
                        if (edge_mode == GaussianEdgeMode::transparent &&
                            (candidate_x < 0 || candidate_x >= static_cast<int>(tile_width))) {
                            continue;
                        }
                        const auto sample_x = static_cast<std::uint32_t>(
                            coordinate(candidate_x, static_cast<int>(tile_width)));
                        const FilterSample& sample = source[index_of(sample_x, y, tile_width)];
                        const float weight = weights[static_cast<std::size_t>(offset + radius)];
                        value.color = value.color + sample.color * weight;
                        value.alpha += sample.alpha * weight;
                    }
                    horizontal[index_of(x, y, tile_width)] = value;
                }
            }
            for (std::uint32_t y = 0U; y < tile_height; ++y) {
                for (std::uint32_t x = 0U; x < tile_width; ++x) {
                    FilterSample value{};
                    for (int offset = -radius; offset <= radius; ++offset) {
                        const int candidate_y = static_cast<int>(y) + offset;
                        if (edge_mode == GaussianEdgeMode::transparent &&
                            (candidate_y < 0 || candidate_y >= static_cast<int>(tile_height))) {
                            continue;
                        }
                        const auto sample_y = static_cast<std::uint32_t>(
                            coordinate(candidate_y, static_cast<int>(tile_height)));
                        const FilterSample& sample = horizontal[index_of(x, sample_y, tile_width)];
                        const float weight = weights[static_cast<std::size_t>(offset + radius)];
                        value.color = value.color + sample.color * weight;
                        value.alpha += sample.alpha * weight;
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
                    output[index_of(core_x + x, core_y + y, image.width)] = combine(
                        row[core_x + x],
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
                    const FilterSample value = output[index_of(x, y, image.width)];
                    row[x].red = value.color.red;
                    row[x].green = value.color.green;
                    row[x].blue = value.color.blue;
                    row[x].alpha = value.alpha;
                }
            }
        });
}

}  // namespace negaflow::imaging::texture_stage_detail
