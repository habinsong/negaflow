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
    const negaflow::color::OutputColorSpace space,
    std::uint64_t& clipped_components) noexcept {
    if (linear < 0.0F || linear > 1.0F) {
        ++clipped_components;
    }
    const float bounded = std::clamp(linear, 0.0F, 1.0F);
    const float encoded = negaflow::color::encode_output_component(bounded, space);
    return static_cast<std::uint16_t>(std::floor(encoded * 65'535.0F + 0.5F));
}

// The primaries change mixes channels, so it runs on the whole pixel before either
// quantizer sees a component. Clipping is counted on the values the file will hold, not on
// the working values - a colour outside the target gamut is clipped by the target.
struct OutputPixel final {
    float red{0.0F};
    float green{0.0F};
    float blue{0.0F};
};

[[nodiscard]] OutputPixel to_output_primaries(
    const negaflow::core::Rgba32F& pixel,
    const negaflow::color::ColorMatrix& matrix) noexcept {
    return {
        (matrix[0] * pixel.red) + (matrix[1] * pixel.green) + (matrix[2] * pixel.blue),
        (matrix[3] * pixel.red) + (matrix[4] * pixel.green) + (matrix[5] * pixel.blue),
        (matrix[6] * pixel.red) + (matrix[7] * pixel.green) + (matrix[8] * pixel.blue),
    };
}

// Same mix as the grain stage. A hash of the absolute coordinate keeps the dither
// reproducible, which the published-file readback check depends on.
[[nodiscard]] std::uint32_t dither_hash(
    const std::uint32_t x,
    const std::uint32_t y,
    const std::uint32_t channel) noexcept {
    std::uint32_t value =
        x * 0x9e3779b9U ^ y * 0x85ebca6bU ^ (channel + 1U) * 0x27d4eb2fU ^ 0xc2b2ae35U;
    value ^= value >> 16U;
    value *= 0x7feb352dU;
    value ^= value >> 15U;
    value *= 0x846ca68bU;
    value ^= value >> 16U;
    return value;
}

[[nodiscard]] std::uint8_t quantize_component_8(
    const float linear,
    const negaflow::color::OutputColorSpace space,
    const std::uint32_t x,
    const std::uint32_t y,
    const std::uint32_t channel,
    std::uint64_t& clipped_components) noexcept {
    if (linear < 0.0F || linear > 1.0F) {
        ++clipped_components;
    }
    const float bounded = std::clamp(linear, 0.0F, 1.0F);
    const float encoded = negaflow::color::encode_output_component(bounded, space);
    const float noise =
        static_cast<float>(dither_hash(x, y, channel) >> 8U) / 16777215.0F - 0.5F;
    const float dithered = std::clamp(encoded + noise / 255.0F, 0.0F, 1.0F);
    return static_cast<std::uint8_t>(std::floor(dithered * 255.0F + 0.5F));
}

void count_clipped_component(
    const float linear,
    std::uint64_t& clipped_components) noexcept {
    if (linear < 0.0F || linear > 1.0F) {
        ++clipped_components;
    }
}

[[nodiscard]] WorkingToSrgb16Result describe_working_as_srgb16(
    const negaflow::imaging::WorkingImage& working,
    const WorkingToSrgb16Limits& limits,
    const std::uint32_t bits_per_sample = 16U) noexcept {
    WorkingToSrgb16Result result{};
    if (bits_per_sample != 8U && bits_per_sample != 16U) {
        result.status = WorkingToSrgb16Status::invalid_dimensions;
        return result;
    }
    result.image.bits_per_sample = bits_per_sample;
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
            bits_per_sample / 8U,
            result.info.encoded_pixel_bytes)) {
        result.status = WorkingToSrgb16Status::size_overflow;
        return result;
    }
    const std::uint64_t stride_bytes =
        static_cast<std::uint64_t>(working.width) * 3U * (result.image.bits_per_sample / 8U);
    if (stride_bytes > std::numeric_limits<std::uint32_t>::max()) {
        result.status = WorkingToSrgb16Status::size_overflow;
        return result;
    }
    if (result.info.encoded_pixel_bytes > limits.max_encoded_pixel_bytes) {
        result.status = WorkingToSrgb16Status::memory_limit_exceeded;
        return result;
    }

    result.image.width = working.width;
    result.image.height = working.height;
    result.image.stride_bytes = static_cast<std::uint32_t>(stride_bytes);
    result.status = WorkingToSrgb16Status::ok;
    return result;
}

}  // namespace

WorkingToSrgb16Result inspect_working_to_srgb16(
    const negaflow::imaging::WorkingImage& working,
    const WorkingToSrgb16Limits& limits) noexcept {
    return inspect_working_to_srgb(working, 16U, limits);
}

WorkingToSrgb16Result inspect_working_to_srgb(
    const negaflow::imaging::WorkingImage& working,
    const std::uint32_t bits_per_sample,
    const WorkingToSrgb16Limits& limits) noexcept {
    WorkingToSrgb16Result result =
        describe_working_as_srgb16(working, limits, bits_per_sample);
    if (result.status != WorkingToSrgb16Status::ok) {
        return result;
    }

    // Rows are independent, so validation splits across cores. The clipped-component
    // total is summed per block and the reported failure is the one on the smallest row.
    std::atomic<std::uint64_t> first_failure{negaflow::core::no_row_failure};
    std::atomic<std::uint64_t> clipped_components{0U};
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
                    count_clipped_component(pixel.red, block_clipped);
                    count_clipped_component(pixel.green, block_clipped);
                    count_clipped_component(pixel.blue, block_clipped);
                }
            }
            clipped_components.fetch_add(block_clipped, std::memory_order_relaxed);
        });

    const std::uint64_t packed = first_failure.load(std::memory_order_relaxed);
    if (negaflow::core::has_row_failure(packed)) {
        result.info.clipped_color_components = 0U;
        result.status = static_cast<WorkingToSrgb16Status>(
            negaflow::core::row_failure_status_value(packed));
        return result;
    }
    result.info.clipped_color_components =
        clipped_components.load(std::memory_order_relaxed);

    result.status = WorkingToSrgb16Status::ok;
    return result;
}

WorkingToSrgb16Status convert_working_to_srgb16_rows(
    const negaflow::imaging::WorkingImage& working,
    const std::uint32_t first_row,
    const std::uint32_t row_count,
    std::uint16_t* const destination_samples,
    const std::size_t destination_sample_capacity,
    std::uint64_t& clipped_color_components,
    const WorkingToSrgb16Limits& limits) noexcept {
    return convert_working_to_srgb_rows(
        working,
        16U,
        first_row,
        row_count,
        reinterpret_cast<std::uint8_t*>(destination_samples),
        destination_sample_capacity * sizeof(std::uint16_t),
        clipped_color_components,
        limits);
}

WorkingToSrgb16Status convert_working_to_srgb_rows(
    const negaflow::imaging::WorkingImage& working,
    const std::uint32_t bits_per_sample,
    const std::uint32_t first_row,
    const std::uint32_t row_count,
    std::uint8_t* const destination_bytes,
    const std::size_t destination_byte_capacity,
    std::uint64_t& clipped_color_components,
    const WorkingToSrgb16Limits& limits) noexcept {
    const WorkingToSrgb16Result description =
        describe_working_as_srgb16(working, limits, bits_per_sample);
    if (description.status != WorkingToSrgb16Status::ok) {
        return description.status;
    }
    if (first_row > working.height || row_count > working.height - first_row) {
        return WorkingToSrgb16Status::invalid_dimensions;
    }
    const std::uint64_t sample_count =
        static_cast<std::uint64_t>(row_count) * working.width * 3U;
    const std::uint64_t byte_count = sample_count * (bits_per_sample / 8U);
    if (byte_count > destination_byte_capacity ||
        (byte_count != 0U && destination_bytes == nullptr)) {
        return WorkingToSrgb16Status::buffer_size_mismatch;
    }

    auto* const samples16 = reinterpret_cast<std::uint16_t*>(destination_bytes);
    const negaflow::color::OutputColorSpace space = limits.color_space;
    const negaflow::color::ColorMatrix matrix = negaflow::color::linear_srgb_to(space);
    clipped_color_components = 0U;
    for (std::uint32_t row = 0U; row < row_count; ++row) {
        const std::uint32_t image_row = first_row + row;
        const std::size_t source_row =
            static_cast<std::size_t>(image_row) * working.stride_pixels;
        const std::size_t destination_row =
            static_cast<std::size_t>(row) * working.width * 3U;
        for (std::uint32_t column = 0U; column < working.width; ++column) {
            const negaflow::core::Rgba32F& pixel = working.pixels[source_row + column];
            if (!std::isfinite(pixel.red) || !std::isfinite(pixel.green) ||
                !std::isfinite(pixel.blue) || !std::isfinite(pixel.alpha)) {
                return WorkingToSrgb16Status::non_finite_pixel;
            }
            if (pixel.alpha != 1.0F) {
                return WorkingToSrgb16Status::non_opaque_alpha;
            }
            const OutputPixel output = to_output_primaries(pixel, matrix);
            const std::size_t destination =
                destination_row + static_cast<std::size_t>(column) * 3U;
            if (bits_per_sample == 8U) {
                destination_bytes[destination] = quantize_component_8(
                    output.red, space, column, image_row, 0U, clipped_color_components);
                destination_bytes[destination + 1U] = quantize_component_8(
                    output.green, space, column, image_row, 1U, clipped_color_components);
                destination_bytes[destination + 2U] = quantize_component_8(
                    output.blue, space, column, image_row, 2U, clipped_color_components);
                continue;
            }
            samples16[destination] =
                quantize_component(output.red, space, clipped_color_components);
            samples16[destination + 1U] =
                quantize_component(output.green, space, clipped_color_components);
            samples16[destination + 2U] =
                quantize_component(output.blue, space, clipped_color_components);
        }
    }
    return WorkingToSrgb16Status::ok;
}

WorkingToSrgb16Result convert_working_to_srgb16(
    const negaflow::imaging::WorkingImage& working,
    const WorkingToSrgb16Limits& limits) noexcept {
    WorkingToSrgb16Result result = describe_working_as_srgb16(working, limits);
    if (result.status != WorkingToSrgb16Status::ok) {
        return result;
    }

    const std::size_t packed_sample_count =
        static_cast<std::size_t>(result.info.encoded_pixel_bytes / sizeof(std::uint16_t));
    try {
        result.image.samples.resize(packed_sample_count);
    } catch (const std::bad_alloc&) {
        result.image = {};
        result.status = WorkingToSrgb16Status::allocation_failed;
        return result;
    }

    const negaflow::color::OutputColorSpace space = limits.color_space;
    const negaflow::color::ColorMatrix matrix = negaflow::color::linear_srgb_to(space);
    const std::uint64_t work_units =
        static_cast<std::uint64_t>(working.width) *
        static_cast<std::uint64_t>(working.height);
    std::atomic<std::uint64_t> first_failure{negaflow::core::no_row_failure};
    std::atomic<std::uint64_t> clipped_components{0U};
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
                    const OutputPixel output = to_output_primaries(pixel, matrix);
                    const std::size_t destination =
                        destination_row + static_cast<std::size_t>(column) * 3U;
                    result.image.samples[destination] =
                        quantize_component(output.red, space, block_clipped);
                    result.image.samples[destination + 1U] =
                        quantize_component(output.green, space, block_clipped);
                    result.image.samples[destination + 2U] =
                        quantize_component(output.blue, space, block_clipped);
                }
            }
            clipped_components.fetch_add(block_clipped, std::memory_order_relaxed);
        });

    const std::uint64_t packed = first_failure.load(std::memory_order_relaxed);
    if (negaflow::core::has_row_failure(packed)) {
        result.image = {};
        result.info.clipped_color_components = 0U;
        result.status = static_cast<WorkingToSrgb16Status>(
            negaflow::core::row_failure_status_value(packed));
        return result;
    }
    result.info.clipped_color_components =
        clipped_components.load(std::memory_order_relaxed);
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
