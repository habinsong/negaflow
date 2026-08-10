#include "negaflow/output/working_to_srgb16.h"

#include "negaflow/color/srgb_transfer.h"
#include "negaflow/core/parallel_rows.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <limits>
#include <new>

namespace negaflow::output {
namespace {

[[nodiscard]] bool checked_multiply(
    const std::uint64_t left,
    const std::uint64_t right,
    std::uint64_t& product) noexcept {
    if (left != 0U && right > std::numeric_limits<std::uint64_t>::max() / left) {
        return false;
    }
    product = left * right;
    return true;
}

[[nodiscard]] std::uint16_t quantize_component(
    const float linear,
    std::uint64_t& clipped_components) noexcept {
    if (linear < 0.0F || linear > 1.0F) {
        ++clipped_components;
    }
    const float bounded = std::clamp(linear, 0.0F, 1.0F);
    const float encoded = negaflow::color::linear_to_srgb_encoded(bounded);
    return static_cast<std::uint16_t>(std::floor(encoded * 65'535.0F + 0.5F));
}

}  // namespace

WorkingToSrgb16Result convert_working_to_srgb16(
    const negaflow::imaging::WorkingImage& working,
    const WorkingToSrgb16Limits& limits) noexcept {
    WorkingToSrgb16Result result{};
    if (working.width == 0U || working.height == 0U) {
        return result;
    }
    if (working.stride_pixels < working.width) {
        result.status = WorkingToSrgb16Status::invalid_stride;
        return result;
    }

    std::uint64_t working_pixel_count = 0U;
    if (!checked_multiply(working.stride_pixels, working.height, working_pixel_count) ||
        working_pixel_count > std::numeric_limits<std::size_t>::max()) {
        result.status = WorkingToSrgb16Status::size_overflow;
        return result;
    }
    if (working.pixels.size() != static_cast<std::size_t>(working_pixel_count)) {
        result.status = WorkingToSrgb16Status::buffer_size_mismatch;
        return result;
    }

    std::uint64_t packed_sample_count = 0U;
    if (!checked_multiply(working.width, working.height, packed_sample_count) ||
        !checked_multiply(packed_sample_count, 3U, packed_sample_count) ||
        packed_sample_count > std::numeric_limits<std::size_t>::max() ||
        !checked_multiply(
            packed_sample_count,
            sizeof(std::uint16_t),
            result.info.encoded_pixel_bytes)) {
        result.status = WorkingToSrgb16Status::size_overflow;
        return result;
    }
    const std::uint64_t stride_bytes =
        static_cast<std::uint64_t>(working.width) * 3U * sizeof(std::uint16_t);
    if (stride_bytes > std::numeric_limits<std::uint32_t>::max()) {
        result.status = WorkingToSrgb16Status::size_overflow;
        return result;
    }
    if (result.info.encoded_pixel_bytes > limits.max_encoded_pixel_bytes) {
        result.status = WorkingToSrgb16Status::memory_limit_exceeded;
        return result;
    }

    // Rows are independent, so the encode splits across cores. The clipped-component
    // total is summed per block and the reported failure is the one on the smallest row,
    // which keeps both figures identical to the single-threaded pass.
    std::atomic<std::uint64_t> first_failure{negaflow::core::no_row_failure};
    std::atomic<std::uint64_t> clipped_components{0U};
    try {
        result.image.samples.resize(static_cast<std::size_t>(packed_sample_count));
        const std::uint64_t work_units =
            static_cast<std::uint64_t>(working.width) *
            static_cast<std::uint64_t>(working.height);
        negaflow::core::for_each_row_block(
            working.height,
            work_units,
            [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
                std::uint64_t block_clipped = 0U;
                for (std::uint32_t row = first_row; row < first_row + row_count; ++row) {
                    const std::size_t source_row =
                        static_cast<std::size_t>(row) * working.stride_pixels;
                    const std::size_t destination_row =
                        static_cast<std::size_t>(row) * working.width * 3U;
                    for (std::uint32_t column = 0U; column < working.width; ++column) {
                        const negaflow::core::Rgba32F& pixel =
                            working.pixels[source_row + column];
                        if (!std::isfinite(pixel.red) || !std::isfinite(pixel.green) ||
                            !std::isfinite(pixel.blue) || !std::isfinite(pixel.alpha)) {
                            negaflow::core::record_row_failure(
                                first_failure,
                                row,
                                WorkingToSrgb16Status::non_finite_pixel);
                            clipped_components.fetch_add(
                                block_clipped, std::memory_order_relaxed);
                            return;
                        }
                        if (pixel.alpha != 1.0F) {
                            negaflow::core::record_row_failure(
                                first_failure,
                                row,
                                WorkingToSrgb16Status::non_opaque_alpha);
                            clipped_components.fetch_add(
                                block_clipped, std::memory_order_relaxed);
                            return;
                        }

                        const std::size_t destination =
                            destination_row + static_cast<std::size_t>(column) * 3U;
                        result.image.samples[destination] =
                            quantize_component(pixel.red, block_clipped);
                        result.image.samples[destination + 1U] =
                            quantize_component(pixel.green, block_clipped);
                        result.image.samples[destination + 2U] =
                            quantize_component(pixel.blue, block_clipped);
                    }
                }
                clipped_components.fetch_add(block_clipped, std::memory_order_relaxed);
            });
    } catch (const std::bad_alloc&) {
        std::vector<std::uint16_t>{}.swap(result.image.samples);
        result.status = WorkingToSrgb16Status::allocation_failed;
        return result;
    }

    const std::uint64_t packed = first_failure.load(std::memory_order_relaxed);
    if (negaflow::core::has_row_failure(packed)) {
        std::vector<std::uint16_t>{}.swap(result.image.samples);
        result.info.clipped_color_components = 0U;
        result.status = static_cast<WorkingToSrgb16Status>(
            negaflow::core::row_failure_status_value(packed));
        return result;
    }
    result.info.clipped_color_components =
        clipped_components.load(std::memory_order_relaxed);

    result.image.width = working.width;
    result.image.height = working.height;
    result.image.stride_bytes = static_cast<std::uint32_t>(stride_bytes);
    result.status = WorkingToSrgb16Status::ok;
    return result;
}

const char* working_to_srgb16_status_name(const WorkingToSrgb16Status status) noexcept {
    switch (status) {
        case WorkingToSrgb16Status::ok:
            return "ok";
        case WorkingToSrgb16Status::invalid_dimensions:
            return "invalid_dimensions";
        case WorkingToSrgb16Status::invalid_stride:
            return "invalid_stride";
        case WorkingToSrgb16Status::size_overflow:
            return "size_overflow";
        case WorkingToSrgb16Status::buffer_size_mismatch:
            return "buffer_size_mismatch";
        case WorkingToSrgb16Status::memory_limit_exceeded:
            return "memory_limit_exceeded";
        case WorkingToSrgb16Status::non_finite_pixel:
            return "non_finite_pixel";
        case WorkingToSrgb16Status::non_opaque_alpha:
            return "non_opaque_alpha";
        case WorkingToSrgb16Status::allocation_failed:
            return "allocation_failed";
    }
    return "unknown";
}

}  // namespace negaflow::output
